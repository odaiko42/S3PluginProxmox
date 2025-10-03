#!/bin/bash

# Installation rapide MinIO via Docker (plus rapide que le téléchargement direct)
# Serveur cible: 192.168.88.50

set -e

echo "=== Installation MinIO via Docker (méthode rapide) ==="
echo "Serveur: $(hostname -I | awk '{print $1}')"

# Variables
MINIO_USER="minioadmin" 
MINIO_PASSWORD="minioadmin123"
MINIO_DATA_DIR="/opt/minio/data"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"

# Vérifier si nous sommes root
if [ "$(id -u)" != "0" ]; then
   echo "ERREUR: Ce script doit être exécuté en tant que root"
   exit 1
fi

# Installer Docker si pas présent
if ! command -v docker > /dev/null 2>&1; then
    echo "Installation de Docker..."
    apt update
    apt install -y docker.io
    systemctl enable docker
    systemctl start docker
    echo "✓ Docker installé"
else
    echo "✓ Docker déjà installé"
fi

# Créer le répertoire de données
echo "Création du répertoire de données..."
mkdir -p "$MINIO_DATA_DIR"
chmod 755 "$MINIO_DATA_DIR"

# Arrêter le conteneur existant s'il existe
if docker ps -a | grep -q "minio-server"; then
    echo "Arrêt du conteneur MinIO existant..."
    docker stop minio-server 2>/dev/null || true
    docker rm minio-server 2>/dev/null || true
fi

# Démarrer MinIO avec Docker
echo "Démarrage de MinIO avec Docker..."
docker run -d \
  --name minio-server \
  --restart unless-stopped \
  -p $MINIO_PORT:9000 \
  -p $MINIO_CONSOLE_PORT:9001 \
  -e MINIO_ROOT_USER="$MINIO_USER" \
  -e MINIO_ROOT_PASSWORD="$MINIO_PASSWORD" \
  -v "$MINIO_DATA_DIR":/data \
  minio/minio server /data --console-address ":9001"

# Attendre que MinIO démarre
echo "Attente du démarrage de MinIO..."
sleep 10

# Vérifier que MinIO répond
SERVER_IP=$(hostname -I | awk '{print $1}')
if curl -s "http://localhost:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
    echo "✅ MinIO est opérationnel"
else
    echo "⚠️  MinIO ne répond pas encore, vérification des logs..."
    docker logs minio-server --tail 20
fi

# Configuration du firewall
echo "Configuration du firewall..."
if command -v ufw > /dev/null 2>&1; then
    ufw allow $MINIO_PORT/tcp
    ufw allow $MINIO_CONSOLE_PORT/tcp
    echo "✓ Ports ouverts dans UFW"
fi

# Installer le client MinIO
echo "Installation du client MinIO..."
wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configurer le client
sleep 3
/usr/local/bin/mc alias set local "http://localhost:$MINIO_PORT" "$MINIO_USER" "$MINIO_PASSWORD"

# Créer le bucket de test
BUCKET_NAME="proxmox-test"
if /usr/local/bin/mc mb local/$BUCKET_NAME 2>/dev/null; then
    echo "✓ Bucket '$BUCKET_NAME' créé"
else
    echo "⚠️  Bucket existe déjà ou erreur de création"
fi

echo ""
echo "============================================"
echo "         MINIO DOCKER INSTALLÉ"
echo "============================================"
echo ""
echo "🎯 Configuration MinIO:"
echo "   Endpoint:     http://$SERVER_IP:$MINIO_PORT"
echo "   Console:      http://$SERVER_IP:$MINIO_CONSOLE_PORT"
echo "   Access Key:   $MINIO_USER"
echo "   Secret Key:   $MINIO_PASSWORD"
echo "   Bucket test:  $BUCKET_NAME"
echo ""
echo "🐋 Commandes Docker utiles:"
echo "   Status:       docker ps | grep minio"
echo "   Logs:         docker logs minio-server -f"
echo "   Restart:      docker restart minio-server"
echo "   Stop:         docker stop minio-server"
echo ""
echo "🔧 Configuration Proxmox S3 Plugin:"
echo "   Endpoint:     $SERVER_IP:$MINIO_PORT"
echo "   Use SSL:      Non"
echo "   Port:         $MINIO_PORT"
echo ""

# Test final
echo "🧪 Test de connectivité..."
if curl -s "http://localhost:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
    echo "✅ MinIO répond correctement"
else
    echo "❌ MinIO ne répond pas"
fi

echo ""
echo "Installation terminée !"