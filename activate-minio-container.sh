#!/bin/bash

# Script pour activer et configurer le conteneur MinIO existant (CT 106)
# Serveur: 192.168.88.50

set -e

echo "=== Activation du conteneur MinIO existant ==="
echo "Conteneur ID: 106 (minio-glovary)"
echo "Date: $(date)"

CT_ID="106"
CT_IP="192.168.88.90"
MINIO_PORT="9000"
CONSOLE_PORT="9001"

# Vérifier que nous sommes sur l'hôte Proxmox
if [ "$(id -u)" != "0" ]; then
   echo "ERREUR: Ce script doit être exécuté en tant que root sur l'hôte Proxmox"
   exit 1
fi

# Vérifier que le conteneur existe
if ! pct list | grep -q "^$CT_ID "; then
    echo "ERREUR: Conteneur $CT_ID non trouvé"
    echo "Conteneurs disponibles:"
    pct list
    exit 1
fi

echo "✓ Conteneur $CT_ID trouvé"

# Afficher la configuration actuelle
echo ""
echo "📋 Configuration du conteneur:"
pct config $CT_ID | grep -E "hostname|net[0-9]|memory|cores"

# Vérifier le statut
CT_STATUS=$(pct status $CT_ID | awk '{print $2}')
echo ""
echo "🔍 Statut actuel: $CT_STATUS"

if [ "$CT_STATUS" = "stopped" ]; then
    echo "▶️  Démarrage du conteneur..."
    if pct start $CT_ID; then
        echo "✅ Conteneur démarré"
        
        # Attendre que le conteneur soit prêt
        echo "⏳ Attente du démarrage (15s)..."
        sleep 15
        
        # Vérifier que le conteneur répond
        if pct exec $CT_ID -- echo "Container is responsive" 2>/dev/null; then
            echo "✅ Conteneur opérationnel"
        else
            echo "⚠️  Conteneur démarré mais ne répond pas encore"
        fi
    else
        echo "❌ Échec du démarrage du conteneur"
        exit 1
    fi
else
    echo "✅ Conteneur déjà en cours d'exécution"
fi

# Vérifier la connectivité réseau
echo ""
echo "🌐 Test de connectivité réseau..."
if ping -c 2 -W 3 "$CT_IP" > /dev/null 2>&1; then
    echo "✅ Conteneur accessible sur $CT_IP"
else
    echo "⚠️  Conteneur non accessible sur $CT_IP"
    echo "   Vérification de la configuration réseau..."
    pct config $CT_ID | grep net
fi

# Vérifier si MinIO est installé dans le conteneur
echo ""
echo "🔍 Vérification de MinIO dans le conteneur..."

# Test simple de commande dans le conteneur
if pct exec $CT_ID -- which minio > /dev/null 2>&1; then
    echo "✅ MinIO binaire trouvé"
    MINIO_VERSION=$(pct exec $CT_ID -- minio --version 2>/dev/null | head -1 || echo "Version inconnue")
    echo "   Version: $MINIO_VERSION"
elif pct exec $CT_ID -- which docker > /dev/null 2>&1; then
    echo "✅ Docker trouvé, vérification des conteneurs MinIO..."
    DOCKER_MINIO=$(pct exec $CT_ID -- docker ps -a | grep minio || echo "Aucun")
    echo "   Conteneurs MinIO: $DOCKER_MINIO"
else
    echo "⚠️  MinIO non trouvé, installation nécessaire"
fi

# Test de connectivité MinIO
echo ""
echo "🧪 Test de connectivité MinIO..."

# Test des ports standards
for port in $MINIO_PORT $CONSOLE_PORT; do
    echo "   → Test du port $port..."
    if curl -s --connect-timeout 5 "http://$CT_IP:$port/minio/health/live" > /dev/null 2>&1; then
        echo "   ✅ MinIO API répond sur port $port"
        MINIO_ACTIVE="true"
    elif curl -s --connect-timeout 5 "http://$CT_IP:$port" > /dev/null 2>&1; then
        echo "   ⚠️  Service répond sur port $port (mais pas MinIO API)"
    else
        echo "   ❌ Aucune réponse sur port $port"
    fi
done

# Installation/Configuration MinIO si nécessaire
if [ "${MINIO_ACTIVE:-false}" != "true" ]; then
    echo ""
    echo "🔧 MinIO non actif, tentative de configuration..."
    
    # Script d'installation MinIO dans le conteneur
    cat > /tmp/install-minio-in-container.sh << 'EOF'
#!/bin/bash
# Installation MinIO dans le conteneur

echo "Installation MinIO dans le conteneur..."

# Mise à jour du système
apt update
apt install -y wget curl

# Téléchargement MinIO
echo "Téléchargement MinIO..."
wget -O /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x /usr/local/bin/minio

# Création des répertoires
mkdir -p /opt/minio/data
mkdir -p /etc/minio

# Création du service systemd
cat > /etc/systemd/system/minio.service << 'EOL'
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/minio server /opt/minio/data --address :9000 --console-address :9001
Restart=always
RestartSec=5
Environment=MINIO_ROOT_USER=minioadmin
Environment=MINIO_ROOT_PASSWORD=minioadmin123

[Install]
WantedBy=multi-user.target
EOL

# Activation du service
systemctl daemon-reload
systemctl enable minio
systemctl start minio

# Attendre le démarrage
sleep 5

# Installation du client mc
wget -O /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x /usr/local/bin/mc

# Configuration du client
/usr/local/bin/mc alias set local http://localhost:9000 minioadmin minioadmin123
/usr/local/bin/mc mb local/proxmox-test

echo "Installation MinIO terminée"
EOF

    # Copier et exécuter le script dans le conteneur
    pct push $CT_ID /tmp/install-minio-in-container.sh /tmp/install-minio.sh
    
    echo "⚙️  Installation de MinIO dans le conteneur..."
    if pct exec $CT_ID -- bash /tmp/install-minio.sh; then
        echo "✅ MinIO installé dans le conteneur"
        
        # Nouvelle vérification
        sleep 5
        if curl -s --connect-timeout 5 "http://$CT_IP:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
            echo "✅ MinIO maintenant opérationnel"
            MINIO_ACTIVE="true"
        fi
    else
        echo "❌ Échec de l'installation MinIO"
    fi
    
    # Nettoyage
    rm -f /tmp/install-minio-in-container.sh
fi

# Affichage de la configuration finale
echo ""
echo "============================================"
echo "        CONFIGURATION MINIO ACTIVE"
echo "============================================"
echo ""
echo "🎯 Accès MinIO:"
echo "   Conteneur ID: $CT_ID"
echo "   IP:           $CT_IP"
echo "   API:          http://$CT_IP:$MINIO_PORT"
echo "   Console:      http://$CT_IP:$CONSOLE_PORT"
echo ""
echo "🔑 Credentials:"
echo "   Access Key:   minioadmin"
echo "   Secret Key:   minioadmin123"
echo "   Bucket test:  proxmox-test"
echo ""
echo "🔧 Configuration Plugin Proxmox S3:"
echo "   Storage ID:   minio-s3"
echo "   Endpoint:     $CT_IP:$MINIO_PORT"
echo "   Bucket:       proxmox-test"
echo "   Access Key:   minioadmin"
echo "   Secret Key:   minioadmin123"
echo "   Use SSL:      Non"
echo "   Port:         $MINIO_PORT"
echo "   Region:       us-east-1"
echo ""
echo "🧪 Tests:"
echo "   Health:       curl http://$CT_IP:$MINIO_PORT/minio/health/live"
echo "   Console Web:  http://$CT_IP:$CONSOLE_PORT"
echo ""
echo "⚙️  Gestion conteneur:"
echo "   Status:       pct status $CT_ID"
echo "   Stop:         pct stop $CT_ID"
echo "   Start:        pct start $CT_ID"
echo "   Logs:         pct exec $CT_ID -- journalctl -u minio -f"
echo ""

# Test final
echo "🔍 Validation finale..."
if [ "${MINIO_ACTIVE:-false}" = "true" ]; then
    echo "✅ Configuration MinIO validée et opérationnelle"
    echo ""
    echo "🎯 Prochaines étapes:"
    echo "   1. Ouvrir l'interface Proxmox"
    echo "   2. Aller dans Datacenter → Storage → Add"
    echo "   3. Sélectionner 'S3' dans la liste"
    echo "   4. Configurer avec les paramètres ci-dessus"
else
    echo "⚠️  Configuration incomplète - Vérification manuelle requise"
    echo ""
    echo "🔍 Diagnostic:"
    echo "   pct status $CT_ID"
    echo "   pct exec $CT_ID -- systemctl status minio"
    echo "   ping $CT_IP"
fi

echo ""
echo "=== Configuration terminée ==="