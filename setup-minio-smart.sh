#!/bin/bash

# Script d'installation MinIO avec détection des instances existantes
# Vérifie si MinIO existe déjà comme CT, VM, Docker ou service avant installation

set -e

echo "=== Installation MinIO avec détection d'instances existantes ==="
echo "Serveur: $(hostname -I | awk '{print $1}')"
echo "Date: $(date)"

# Variables de configuration
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin123"
MINIO_DATA_DIR="/opt/minio/data"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"

# Fonction de détection MinIO existant
detect_existing_minio() {
    echo ""
    echo "🔍 Détection des instances MinIO existantes..."
    
    local found_instances=0
    local minio_info=""
    
    # 1. Vérifier les conteneurs Proxmox (CT)
    echo "   → Vérification des conteneurs Proxmox..."
    if command -v pct > /dev/null 2>&1; then
        local ct_list=$(pct list 2>/dev/null | grep -i minio || true)
        if [ -n "$ct_list" ]; then
            echo "   ⚠️  Conteneur MinIO détecté:"
            echo "      $ct_list"
            minio_info="${minio_info}\n   - Conteneur Proxmox: $ct_list"
            found_instances=$((found_instances + 1))
        else
            echo "   ✓ Aucun conteneur MinIO trouvé"
        fi
    else
        echo "   ℹ️  Commande pct non disponible (normal si pas sur Proxmox)"
    fi
    
    # 2. Vérifier les VMs Proxmox
    echo "   → Vérification des VMs Proxmox..."
    if command -v qm > /dev/null 2>&1; then
        local vm_list=$(qm list 2>/dev/null | grep -i minio || true)
        if [ -n "$vm_list" ]; then
            echo "   ⚠️  VM MinIO détectée:"
            echo "      $vm_list"
            minio_info="${minio_info}\n   - VM Proxmox: $vm_list"
            found_instances=$((found_instances + 1))
        else
            echo "   ✓ Aucune VM MinIO trouvée"
        fi
    else
        echo "   ℹ️  Commande qm non disponible"
    fi
    
    # 3. Vérifier les conteneurs Docker
    echo "   → Vérification des conteneurs Docker..."
    if command -v docker > /dev/null 2>&1; then
        local docker_containers=$(docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | grep -i minio || true)
        if [ -n "$docker_containers" ]; then
            echo "   ⚠️  Conteneur Docker MinIO détecté:"
            echo "      $docker_containers"
            minio_info="${minio_info}\n   - Conteneur Docker: $docker_containers"
            found_instances=$((found_instances + 1))
        else
            echo "   ✓ Aucun conteneur Docker MinIO trouvé"
        fi
    else
        echo "   ℹ️  Docker non installé"
    fi
    
    # 4. Vérifier les services systemd
    echo "   → Vérification des services systemd..."
    local minio_service=$(systemctl list-units --all | grep -i minio || true)
    if [ -n "$minio_service" ]; then
        echo "   ⚠️  Service MinIO détecté:"
        echo "      $minio_service"
        minio_info="${minio_info}\n   - Service systemd: $minio_service"
        found_instances=$((found_instances + 1))
    else
        echo "   ✓ Aucun service MinIO trouvé"
    fi
    
    # 5. Vérifier les processus en cours
    echo "   → Vérification des processus actifs..."
    local minio_processes=$(ps aux | grep -v grep | grep -i minio || true)
    if [ -n "$minio_processes" ]; then
        echo "   ⚠️  Processus MinIO détecté:"
        echo "      $minio_processes"
        minio_info="${minio_info}\n   - Processus actif: $(echo "$minio_processes" | wc -l) processus"
        found_instances=$((found_instances + 1))
    else
        echo "   ✓ Aucun processus MinIO actif"
    fi
    
    # 6. Vérifier les ports occupés
    echo "   → Vérification des ports $MINIO_PORT et $MINIO_CONSOLE_PORT..."
    local port_check=""
    if command -v ss > /dev/null 2>&1; then
        port_check=$(ss -tlnp | grep ":$MINIO_PORT\|:$MINIO_CONSOLE_PORT" || true)
    elif command -v netstat > /dev/null 2>&1; then
        port_check=$(netstat -tlnp | grep ":$MINIO_PORT\|:$MINIO_CONSOLE_PORT" || true)
    fi
    
    if [ -n "$port_check" ]; then
        echo "   ⚠️  Ports MinIO occupés:"
        echo "      $port_check"
        minio_info="${minio_info}\n   - Ports occupés: $MINIO_PORT/$MINIO_CONSOLE_PORT"
        found_instances=$((found_instances + 1))
    else
        echo "   ✓ Ports MinIO libres"
    fi
    
    # 7. Test de connectivité HTTP
    echo "   → Test de connectivité MinIO..."
    local server_ip=$(hostname -I | awk '{print $1}')
    if curl -s --connect-timeout 3 "http://localhost:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
        echo "   ⚠️  MinIO répond déjà sur localhost:$MINIO_PORT"
        minio_info="${minio_info}\n   - API MinIO active: http://localhost:$MINIO_PORT"
        found_instances=$((found_instances + 1))
    elif curl -s --connect-timeout 3 "http://$server_ip:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
        echo "   ⚠️  MinIO répond déjà sur $server_ip:$MINIO_PORT"
        minio_info="${minio_info}\n   - API MinIO active: http://$server_ip:$MINIO_PORT"
        found_instances=$((found_instances + 1))
    else
        echo "   ✓ Aucune API MinIO active détectée"
    fi
    
    # Résumé de la détection
    echo ""
    echo "📊 Résumé de la détection:"
    echo "   Instances MinIO trouvées: $found_instances"
    
    if [ $found_instances -gt 0 ]; then
        echo "   ⚠️  ATTENTION: MinIO semble déjà installé !"
        echo -e "$minio_info"
        echo ""
        return $found_instances
    else
        echo "   ✅ Aucune instance MinIO détectée - Installation possible"
        echo ""
        return 0
    fi
}

# Fonction pour afficher les instances existantes et demander confirmation
handle_existing_minio() {
    local instances_count=$1
    
    echo "============================================"
    echo "      INSTANCES MINIO EXISTANTES DÉTECTÉES"
    echo "============================================"
    echo ""
    echo "⚠️  $instances_count instance(s) MinIO trouvée(s) sur ce système."
    echo ""
    echo "Options disponibles:"
    echo "  1. Continuer l'installation (peut créer des conflits)"
    echo "  2. Utiliser l'instance existante"
    echo "  3. Arrêter l'installation"
    echo ""
    
    # En mode automatique, on s'arrête par sécurité
    if [ "${AUTO_INSTALL:-false}" = "true" ]; then
        echo "🤖 Mode automatique détecté - Arrêt par sécurité"
        echo ""
        echo "Pour forcer l'installation, utilisez:"
        echo "   FORCE_INSTALL=true $0"
        exit 1
    fi
    
    # Si FORCE_INSTALL est défini, on continue
    if [ "${FORCE_INSTALL:-false}" = "true" ]; then
        echo "🚨 Installation forcée (FORCE_INSTALL=true)"
        echo "   Continuation malgré les instances existantes..."
        return 0
    fi
    
    # Mode interactif
    while true; do
        echo -n "Votre choix [1-3]: "
        read -r choice
        
        case $choice in
            1)
                echo "⚠️  Continuation de l'installation..."
                echo "   Cela peut créer des conflits de ports ou services"
                sleep 2
                return 0
                ;;
            2)
                echo "✅ Utilisation de l'instance existante"
                show_existing_minio_config
                exit 0
                ;;
            3)
                echo "🛑 Installation annulée par l'utilisateur"
                exit 0
                ;;
            *)
                echo "❌ Choix invalide. Veuillez entrer 1, 2 ou 3."
                ;;
        esac
    done
}

# Fonction pour afficher la configuration d'une instance existante
show_existing_minio_config() {
    echo ""
    echo "============================================"
    echo "        CONFIGURATION MINIO EXISTANTE"
    echo "============================================"
    
    local server_ip=$(hostname -I | awk '{print $1}')
    
    # Test des ports standards
    for port in 9000 9001; do
        if curl -s --connect-timeout 3 "http://localhost:$port/minio/health/live" > /dev/null 2>&1; then
            echo ""
            echo "🌐 MinIO trouvé sur port $port:"
            echo "   API:     http://$server_ip:$port"
            if [ "$port" = "9000" ]; then
                echo "   Console: http://$server_ip:9001 (probable)"
            fi
            echo "   Health:  http://$server_ip:$port/minio/health/live"
            echo ""
            echo "🔑 Credentials par défaut à tester:"
            echo "   Access Key: minioadmin"
            echo "   Secret Key: minioadmin / minioadmin123"
            echo ""
            echo "🔧 Configuration pour plugin Proxmox S3:"
            echo "   Endpoint:   $server_ip:$port"
            echo "   Use SSL:    Non"
            echo "   Port:       $port"
        fi
    done
    
    # Afficher les conteneurs Docker s'ils existent
    if command -v docker > /dev/null 2>&1; then
        local docker_info=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -i minio || true)
        if [ -n "$docker_info" ]; then
            echo ""
            echo "🐋 Conteneurs Docker MinIO:"
            echo "$docker_info"
        fi
    fi
    
    echo ""
    echo "Pour tester la connectivité:"
    echo "   curl http://$server_ip:9000/minio/health/live"
    echo "   curl http://$server_ip:9001/minio/health/live"
}

# Fonction d'installation MinIO (version Docker rapide)
install_minio_docker() {
    echo ""
    echo "🚀 Installation MinIO via Docker..."
    
    # Installer Docker si nécessaire
    if ! command -v docker > /dev/null 2>&1; then
        echo "📦 Installation de Docker..."
        apt update
        apt install -y docker.io
        systemctl enable docker
        systemctl start docker
        echo "✓ Docker installé"
    else
        echo "✓ Docker déjà disponible"
    fi
    
    # Créer le répertoire de données
    mkdir -p "$MINIO_DATA_DIR"
    chmod 755 "$MINIO_DATA_DIR"
    
    # Arrêter un éventuel conteneur existant
    docker stop minio-server 2>/dev/null || true
    docker rm minio-server 2>/dev/null || true
    
    # Démarrer MinIO
    echo "🔄 Démarrage du conteneur MinIO..."
    docker run -d \
      --name minio-server \
      --restart unless-stopped \
      -p $MINIO_PORT:9000 \
      -p $MINIO_CONSOLE_PORT:9001 \
      -e MINIO_ROOT_USER="$MINIO_USER" \
      -e MINIO_ROOT_PASSWORD="$MINIO_PASSWORD" \
      -v "$MINIO_DATA_DIR":/data \
      minio/minio server /data --console-address ":9001"
    
    # Attendre le démarrage
    echo "⏳ Attente du démarrage (10s)..."
    sleep 10
    
    # Vérifier le statut
    if docker ps | grep -q "minio-server"; then
        echo "✅ Conteneur MinIO démarré"
    else
        echo "❌ Échec du démarrage du conteneur"
        docker logs minio-server --tail 20
        return 1
    fi
    
    # Configurer le firewall
    if command -v ufw > /dev/null 2>&1; then
        ufw allow $MINIO_PORT/tcp >/dev/null 2>&1 || true
        ufw allow $MINIO_CONSOLE_PORT/tcp >/dev/null 2>&1 || true
    fi
    
    # Installer et configurer le client mc
    if ! command -v mc > /dev/null 2>&1; then
        echo "📥 Installation du client MinIO..."
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
        chmod +x /usr/local/bin/mc
    fi
    
    # Configuration du client et création du bucket
    sleep 3
    local server_ip=$(hostname -I | awk '{print $1}')
    /usr/local/bin/mc alias set local "http://localhost:$MINIO_PORT" "$MINIO_USER" "$MINIO_PASSWORD" >/dev/null 2>&1
    /usr/local/bin/mc mb local/proxmox-test >/dev/null 2>&1 || true
    
    echo ""
    echo "🎉 Installation MinIO terminée avec succès !"
    show_installation_summary "$server_ip"
}

# Fonction d'affichage du résumé d'installation
show_installation_summary() {
    local server_ip=$1
    
    echo ""
    echo "============================================"
    echo "           INSTALLATION TERMINÉE"
    echo "============================================"
    echo ""
    echo "🎯 Configuration MinIO:"
    echo "   API:        http://$server_ip:$MINIO_PORT"
    echo "   Console:    http://$server_ip:$MINIO_CONSOLE_PORT"
    echo "   Access Key: $MINIO_USER"
    echo "   Secret Key: $MINIO_PASSWORD"
    echo "   Bucket:     proxmox-test"
    echo ""
    echo "🔧 Configuration Proxmox S3:"
    echo "   Endpoint:   $server_ip:$MINIO_PORT"
    echo "   Use SSL:    Non"
    echo "   Port:       $MINIO_PORT"
    echo ""
    echo "🧪 Test rapide:"
    echo "   curl http://$server_ip:$MINIO_PORT/minio/health/live"
    echo ""
    echo "🐋 Gestion Docker:"
    echo "   Status:     docker ps | grep minio"
    echo "   Logs:       docker logs minio-server -f"
    echo "   Restart:    docker restart minio-server"
}

# Programme principal
main() {
    # Vérifier les privilèges root
    if [ "$(id -u)" != "0" ]; then
       echo "ERREUR: Ce script doit être exécuté en tant que root"
       exit 1
    fi
    
    # Détection des instances existantes
    detect_existing_minio
    instances_found=$?
    
    # Gestion des instances existantes
    if [ $instances_found -gt 0 ]; then
        handle_existing_minio $instances_found
    fi
    
    # Si on arrive ici, on peut installer
    echo "▶️  Début de l'installation MinIO..."
    install_minio_docker
    
    # Test final
    echo ""
    echo "🔍 Vérification finale..."
    local server_ip=$(hostname -I | awk '{print $1}')
    if curl -s --connect-timeout 5 "http://localhost:$MINIO_PORT/minio/health/live" > /dev/null 2>&1; then
        echo "✅ MinIO opérationnel et accessible"
    else
        echo "⚠️  MinIO installé mais ne répond pas encore"
        echo "   Attendez quelques secondes et testez manuellement"
    fi
    
    echo ""
    echo "🎯 Installation terminée ! Vous pouvez maintenant configurer le plugin S3 dans Proxmox."
}

# Exécution du programme principal
main "$@"