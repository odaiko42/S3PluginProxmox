#!/bin/bash

# Script pour déployer et configurer MinIO sur le serveur Proxmox
# Usage: ./deploy-minio.sh

SERVER_IP="192.168.88.50"
SERVER_USER="root"
SCRIPT_NAME="setup-minio-server.sh"

echo "=== Déploiement MinIO sur serveur Proxmox ==="
echo "Serveur cible: $SERVER_IP"
echo "Utilisateur: $SERVER_USER"
echo ""

# Vérifier que le script existe
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "ERREUR: Script $SCRIPT_NAME non trouvé dans le répertoire courant"
    exit 1
fi

# Test de connectivité SSH
echo "🔍 Test de connectivité SSH..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SERVER_USER@$SERVER_IP" "echo 'SSH OK'" 2>/dev/null; then
    echo "ERREUR: Impossible de se connecter en SSH à $SERVER_USER@$SERVER_IP"
    echo "Vérifiez:"
    echo "  - L'adresse IP du serveur"
    echo "  - Les clés SSH ou credentials"
    echo "  - La connectivité réseau"
    exit 1
fi

echo "✅ Connexion SSH OK"
echo ""

# Copier le script sur le serveur
echo "📤 Copie du script d'installation..."
if scp "$SCRIPT_NAME" "$SERVER_USER@$SERVER_IP:/tmp/$SCRIPT_NAME"; then
    echo "✅ Script copié vers /tmp/$SCRIPT_NAME"
else
    echo "ERREUR: Échec de la copie du script"
    exit 1
fi

# Rendre le script exécutable et l'exécuter
echo ""
echo "🚀 Exécution du script d'installation sur le serveur..."
echo "----------------------------------------"

ssh "$SERVER_USER@$SERVER_IP" "chmod +x /tmp/$SCRIPT_NAME && /tmp/$SCRIPT_NAME"

INSTALL_STATUS=$?

echo "----------------------------------------"

if [ $INSTALL_STATUS -eq 0 ]; then
    echo ""
    echo "🎉 Installation MinIO terminée avec succès !"
    echo ""
    echo "📋 Informations de connexion:"
    echo "   Console MinIO: http://$SERVER_IP:9001"
    echo "   API MinIO:     http://$SERVER_IP:9000"
    echo "   Access Key:    minioadmin"
    echo "   Secret Key:    minioadmin123"
    echo ""
    echo "🔧 Configuration pour plugin Proxmox S3:"
    echo "   Endpoint:      $SERVER_IP:9000"
    echo "   Bucket:        proxmox-test"
    echo "   Access Key:    minioadmin"
    echo "   Secret Key:    minioadmin123"
    echo "   Use SSL:       Non"
    echo "   Port:          9000"
    echo ""
    echo "🧪 Test rapide:"
    echo "   curl http://$SERVER_IP:9000/minio/health/live"
    echo ""
    
    # Test de connectivité
    echo "🔍 Test de connectivité MinIO..."
    if curl -s "http://$SERVER_IP:9000/minio/health/live" > /dev/null 2>&1; then
        echo "✅ MinIO répond correctement"
    else
        echo "⚠️  MinIO ne répond pas encore (peut prendre quelques secondes)"
    fi
    
    echo ""
    echo "📝 Prochaines étapes:"
    echo "1. Ouvrir la console MinIO: http://$SERVER_IP:9001"
    echo "2. Se connecter avec minioadmin / minioadmin123"
    echo "3. Configurer le plugin S3 dans Proxmox"
    echo "4. Tester les backups"
    
else
    echo ""
    echo "❌ Échec de l'installation MinIO"
    echo ""
    echo "🔍 Pour diagnostiquer:"
    echo "   ssh $SERVER_USER@$SERVER_IP"
    echo "   journalctl -u minio -n 50"
    echo "   systemctl status minio"
fi

# Nettoyer le script temporaire
ssh "$SERVER_USER@$SERVER_IP" "rm -f /tmp/$SCRIPT_NAME" 2>/dev/null || true

echo ""
echo "=== Déploiement terminé ==="