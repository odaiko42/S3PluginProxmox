#!/bin/bash

# Script d'installation et configuration MinIO sur serveur Proxmox
# Serveur cible: 192.168.88.50
# Ce script configure un portail S3 compatible avec notre plugin

set -e

echo "=== Installation et configuration MinIO S3 Server ==="
echo "Serveur cible: $(hostname -I | awk '{print $1}')"
echo "Date: $(date)"

# Variables de configuration
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin123"
MINIO_DATA_DIR="/opt/minio/data"
MINIO_CONFIG_DIR="/opt/minio/config"
MINIO_SERVICE_FILE="/etc/systemd/system/minio.service"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"

# Détection de l'architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        MINIO_ARCH="amd64"
        ;;
    aarch64)
        MINIO_ARCH="arm64"
        ;;
    *)
        echo "ERREUR: Architecture non supportée: $ARCH"
        exit 1
        ;;
esac

echo "Architecture détectée: $ARCH -> MinIO $MINIO_ARCH"

# Vérifier les prérequis
echo ""
echo "=== Vérification des prérequis ==="

# Vérifier que nous sommes root
if [ "$(id -u)" != "0" ]; then
   echo "ERREUR: Ce script doit être exécuté en tant que root"
   exit 1
fi

# Vérifier la connectivité internet
echo "Test de connectivité internet..."
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "ATTENTION: Pas de connectivité internet détectée"
    echo "Assurez-vous d'avoir accès à internet pour télécharger MinIO"
fi

# Arrêter MinIO s'il est déjà en cours d'exécution
if systemctl is-active --quiet minio 2>/dev/null; then
    echo "Arrêt du service MinIO existant..."
    systemctl stop minio
fi

# Créer les répertoires nécessaires
echo ""
echo "=== Création des répertoires ==="
mkdir -p "$MINIO_DATA_DIR"
mkdir -p "$MINIO_CONFIG_DIR"
mkdir -p /usr/local/bin

echo "✓ Répertoires créés:"
echo "  - Données: $MINIO_DATA_DIR"
echo "  - Configuration: $MINIO_CONFIG_DIR"

# Télécharger MinIO
echo ""
echo "=== Téléchargement de MinIO ==="

MINIO_URL="https://dl.min.io/server/minio/release/linux-${MINIO_ARCH}/minio"
echo "Téléchargement depuis: $MINIO_URL"

if command -v wget > /dev/null 2>&1; then
    wget -O /usr/local/bin/minio "$MINIO_URL"
elif command -v curl > /dev/null 2>&1; then
    curl -L -o /usr/local/bin/minio "$MINIO_URL"
else
    echo "ERREUR: wget ou curl requis pour télécharger MinIO"
    exit 1
fi

# Rendre MinIO exécutable
chmod +x /usr/local/bin/minio

# Vérifier l'installation
if [ ! -f /usr/local/bin/minio ]; then
    echo "ERREUR: Échec du téléchargement de MinIO"
    exit 1
fi

echo "✓ MinIO téléchargé et installé"

# Créer un utilisateur pour MinIO (optionnel, peut fonctionner avec root)
if ! id minio > /dev/null 2>&1; then
    echo ""
    echo "=== Création de l'utilisateur MinIO ==="
    useradd -r -s /sbin/nologin -d "$MINIO_DATA_DIR" minio
    echo "✓ Utilisateur 'minio' créé"
else
    echo "✓ Utilisateur 'minio' existe déjà"
fi

# Définir les permissions
chown -R minio:minio "$MINIO_DATA_DIR"
chown -R minio:minio "$MINIO_CONFIG_DIR"

# Créer le fichier de service systemd
echo ""
echo "=== Configuration du service systemd ==="

cat > "$MINIO_SERVICE_FILE" << EOF
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=minio
Group=minio
ExecStart=/usr/local/bin/minio server $MINIO_DATA_DIR --address :$MINIO_PORT --console-address :$MINIO_CONSOLE_PORT
Restart=always
RestartSec=5

# Variables d'environnement MinIO
Environment=MINIO_ROOT_USER=$MINIO_USER
Environment=MINIO_ROOT_PASSWORD=$MINIO_PASSWORD
Environment=MINIO_REGION_NAME=us-east-1

# Sécurité
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$MINIO_DATA_DIR
ReadWritePaths=$MINIO_CONFIG_DIR
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

echo "✓ Service systemd configuré"

# Recharger systemd et activer le service
systemctl daemon-reload
systemctl enable minio

# Ouvrir les ports du firewall (si ufw est installé)
echo ""
echo "=== Configuration du firewall ==="

if command -v ufw > /dev/null 2>&1; then
    echo "Configuration UFW..."
    ufw allow $MINIO_PORT/tcp comment "MinIO API"
    ufw allow $MINIO_CONSOLE_PORT/tcp comment "MinIO Console"
    echo "✓ Ports ouverts dans UFW"
elif command -v firewall-cmd > /dev/null 2>&1; then
    echo "Configuration firewalld..."
    firewall-cmd --permanent --add-port=$MINIO_PORT/tcp
    firewall-cmd --permanent --add-port=$MINIO_CONSOLE_PORT/tcp
    firewall-cmd --reload
    echo "✓ Ports ouverts dans firewalld"
else
    echo "ATTENTION: Aucun firewall détecté. Assurez-vous que les ports $MINIO_PORT et $MINIO_CONSOLE_PORT sont ouverts"
fi

# Démarrer MinIO
echo ""
echo "=== Démarrage de MinIO ==="
systemctl start minio

# Attendre que MinIO soit prêt
echo "Attente du démarrage de MinIO..."
sleep 5

# Vérifier le statut
if systemctl is-active --quiet minio; then
    echo "✓ MinIO est en cours d'exécution"
else
    echo "ERREUR: MinIO n'a pas pu démarrer"
    echo "Vérification des logs:"
    journalctl -u minio -n 20 --no-pager
    exit 1
fi

# Installer le client MinIO (mc) pour la configuration
echo ""
echo "=== Installation du client MinIO (mc) ==="

MC_URL="https://dl.min.io/client/mc/release/linux-${MINIO_ARCH}/mc"
echo "Téléchargement du client MinIO depuis: $MC_URL"

if command -v wget > /dev/null 2>&1; then
    wget -O /usr/local/bin/mc "$MC_URL"
elif command -v curl > /dev/null 2>&1; then
    curl -L -o /usr/local/bin/mc "$MC_URL"
fi

chmod +x /usr/local/bin/mc
echo "✓ Client MinIO (mc) installé"

# Configurer l'alias pour le serveur local
echo ""
echo "=== Configuration du client MinIO ==="

SERVER_IP=$(hostname -I | awk '{print $1}')
MINIO_ENDPOINT="http://$SERVER_IP:$MINIO_PORT"

# Attendre que MinIO soit complètement prêt
sleep 3

/usr/local/bin/mc alias set local "$MINIO_ENDPOINT" "$MINIO_USER" "$MINIO_PASSWORD"

if [ $? -eq 0 ]; then
    echo "✓ Client configuré pour le serveur local"
else
    echo "ATTENTION: Impossible de configurer le client MinIO automatiquement"
    echo "Vous pourrez le faire manuellement après le démarrage"
fi

# Créer un bucket de test pour Proxmox
echo ""
echo "=== Création du bucket de test ==="

BUCKET_NAME="proxmox-test"
sleep 2

if /usr/local/bin/mc mb local/$BUCKET_NAME 2>/dev/null; then
    echo "✓ Bucket '$BUCKET_NAME' créé"
    
    # Définir une politique publique pour le test (optionnel)
    /usr/local/bin/mc anonymous set public local/$BUCKET_NAME 2>/dev/null || true
else
    echo "ATTENTION: Impossible de créer le bucket automatiquement"
fi

# Affichage des informations de configuration
echo ""
echo "============================================================"
echo "              INSTALLATION TERMINÉE AVEC SUCCÈS"
echo "============================================================"
echo ""
echo "🎯 Configuration MinIO:"
echo "   Endpoint:     http://$SERVER_IP:$MINIO_PORT"
echo "   Console:      http://$SERVER_IP:$MINIO_CONSOLE_PORT"
echo "   Access Key:   $MINIO_USER"
echo "   Secret Key:   $MINIO_PASSWORD"
echo "   Region:       us-east-1"
echo ""
echo "📁 Répertoires:"
echo "   Données:      $MINIO_DATA_DIR"
echo "   Configuration: $MINIO_CONFIG_DIR"
echo ""
echo "🔧 Configuration Proxmox S3 Plugin:"
echo "   Storage ID:   minio-s3"
echo "   Endpoint:     $SERVER_IP:$MINIO_PORT"
echo "   Bucket:       $BUCKET_NAME"
echo "   Access Key:   $MINIO_USER"
echo "   Secret Key:   $MINIO_PASSWORD"
echo "   Port:         $MINIO_PORT"
echo "   Use SSL:      Non"
echo "   Region:       us-east-1"
echo ""
echo "🌐 Accès Web:"
echo "   Console MinIO: http://$SERVER_IP:$MINIO_CONSOLE_PORT"
echo "   (Utilisez les mêmes credentials pour vous connecter)"
echo ""
echo "⚙️  Commandes utiles:"
echo "   Status:       systemctl status minio"
echo "   Logs:         journalctl -u minio -f"
echo "   Restart:      systemctl restart minio"
echo "   Client:       mc --help"
echo "   List buckets: mc ls local/"
echo ""
echo "🧪 Test de connectivité:"
echo "   curl http://$SERVER_IP:$MINIO_PORT/minio/health/live"
echo ""
echo "============================================================"

# Test de connectivité final
echo "🔍 Test de connectivité final..."
sleep 2

if curl -s "http://$SERVER_IP:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
    echo "✅ MinIO est accessible et répond correctement"
else
    echo "⚠️  MinIO ne répond pas sur le port API"
    echo "   Vérifiez les logs: journalctl -u minio -f"
fi

echo ""
echo "Installation terminée ! Vous pouvez maintenant configurer le plugin S3 dans Proxmox."