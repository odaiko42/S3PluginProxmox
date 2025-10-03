#!/bin/bash

# Script d'installation et configuration automatique du plugin Proxmox S3
# Basé sur la structure de proxmox-s3-installer.py
# Version: 1.0.0

set -e

# Configuration globale
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Proxmox S3 Plugin Installer"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Providers S3 supportés
declare -A S3_PROVIDERS=(
    ["1"]="AWS S3|s3.{region}.amazonaws.com|us-east-1|true|false"
    ["2"]="MinIO|{custom_endpoint}|us-east-1|false|true"
    ["3"]="Ceph RadosGW|{custom_endpoint}|default|false|true"
    ["4"]="Wasabi|s3.wasabisys.com|us-east-1|true|false"
    ["5"]="Backblaze B2|s3.{region}.backblazeb2.com|us-west-002|true|false"
    ["6"]="DigitalOcean Spaces|{region}.digitaloceanspaces.com|fra1|true|false"
    ["7"]="OVHcloud Object Storage|s3.{region}.io.cloud.ovh.net|gra|true|false"
    ["8"]="Autre (personnalisé)|{custom_endpoint}|us-east-1|true|false"
)

# Variables de configuration
PROXMOX_HOST=""
PROXMOX_USER="root"
SSH_KEY_PATH=""
STORAGE_CONFIG=()

# Fonctions utilitaires
print_header() {
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${WHITE}🚀 ${SCRIPT_NAME} - v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${CYAN}📡 Serveur cible: ${PROXMOX_HOST}${NC}"
    echo -e "${CYAN}👤 Utilisateur: ${PROXMOX_USER}${NC}"
    echo -e "${CYAN}⏰ Date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${PURPLE}▶️  $1${NC}"
}

# Fonction SSH sécurisée
ssh_exec() {
    local command="$1"
    local description="$2"
    
    if [ -n "$description" ]; then
        log_step "$description"
    fi
    
    if [ -n "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "$command"
    else
        ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "$command"
    fi
}

scp_copy() {
    local local_file="$1"
    local remote_file="$2"
    local description="$3"
    
    if [ -n "$description" ]; then
        log_step "$description"
    fi
    
    if [ -n "$SSH_KEY_PATH" ]; then
        scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$local_file" "$PROXMOX_USER@$PROXMOX_HOST:$remote_file"
    else
        scp -o StrictHostKeyChecking=no "$local_file" "$PROXMOX_USER@$PROXMOX_HOST:$remote_file"
    fi
}

# Vérification de l'environnement local
check_local_environment() {
    log_step "Vérification de l'environnement local"
    
    # Vérifier SSH
    if ! command -v ssh > /dev/null 2>&1; then
        log_error "SSH client non trouvé. Veuillez l'installer."
        exit 1
    fi
    
    # Vérifier SCP
    if ! command -v scp > /dev/null 2>&1; then
        log_error "SCP client non trouvé. Veuillez l'installer."
        exit 1
    fi
    
    # Vérifier les fichiers du plugin
    if [ ! -f "S3Plugin.pm" ]; then
        log_error "Fichier S3Plugin.pm non trouvé dans le répertoire courant"
        exit 1
    fi
    
    log_success "Environnement local vérifié"
}

# Test de connectivité SSH
test_ssh_connection() {
    log_step "Test de la connexion SSH vers $PROXMOX_HOST"
    
    if ssh_exec "echo 'SSH OK'" "Test de connectivité" > /dev/null 2>&1; then
        local hostname=$(ssh_exec "hostname" "")
        log_success "Connexion SSH réussie vers $hostname"
        return 0
    else
        log_error "Impossible de se connecter en SSH à $PROXMOX_HOST"
        log_info "Vérifiez :"
        log_info "  - L'adresse IP du serveur"
        log_info "  - Les clés SSH ou credentials"
        log_info "  - La connectivité réseau"
        return 1
    fi
}

# Vérification de l'environnement Proxmox
check_proxmox_environment() {
    log_step "Vérification de l'environnement Proxmox"
    
    # Vérifier la version Proxmox
    local pve_version=$(ssh_exec "pveversion 2>/dev/null || echo 'Non installé'" "")
    log_info "Version Proxmox : $pve_version"
    
    if [[ "$pve_version" == *"Non installé"* ]]; then
        log_error "Proxmox VE non détecté sur le serveur"
        return 1
    fi
    
    # Vérifier les services
    local pvedaemon_status=$(ssh_exec "systemctl is-active pvedaemon 2>/dev/null || echo 'inactive'" "")
    local pveproxy_status=$(ssh_exec "systemctl is-active pveproxy 2>/dev/null || echo 'inactive'" "")
    
    if [ "$pvedaemon_status" = "active" ]; then
        log_success "Service pvedaemon : actif"
    else
        log_warning "Service pvedaemon : problème détecté"
    fi
    
    if [ "$pveproxy_status" = "active" ]; then
        log_success "Service pveproxy : actif"
    else
        log_warning "Service pveproxy : problème détecté"
    fi
    
    return 0
}

# Sauvegarde de la configuration existante
backup_existing_config() {
    log_step "Sauvegarde de la configuration existante"
    
    # Sauvegarder storage.cfg
    ssh_exec "cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup_$TIMESTAMP" "Sauvegarde storage.cfg"
    
    # Sauvegarder Storage.pm si modifié
    ssh_exec "cp /usr/share/perl5/PVE/Storage.pm /usr/share/perl5/PVE/Storage.pm.backup_$TIMESTAMP 2>/dev/null || true" "Sauvegarde Storage.pm"
    
    log_success "Configuration sauvegardée avec timestamp $TIMESTAMP"
}

# Installation des fichiers du plugin
install_plugin_files() {
    log_step "Installation des fichiers du plugin S3"
    
    # Créer les répertoires nécessaires
    ssh_exec "mkdir -p /usr/share/perl5/PVE/Storage/Custom" "Création des répertoires"
    ssh_exec "mkdir -p /etc/pve/s3-credentials" "Création du répertoire credentials"
    
    # Copier le plugin principal
    scp_copy "S3Plugin.pm" "/usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm" "Copie du plugin S3"
    
    # Définir les permissions
    ssh_exec "chown root:root /usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm" ""
    ssh_exec "chmod 644 /usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm" ""
    
    log_success "Fichiers du plugin installés"
}

# Enregistrement du plugin dans Storage.pm
register_plugin_in_storage() {
    log_step "Enregistrement du plugin dans Storage.pm"
    
    # Vérifier si le plugin n'est pas déjà enregistré
    local plugin_registered=$(ssh_exec "grep -c 'S3Plugin' /usr/share/perl5/PVE/Storage.pm || echo '0'" "")
    
    if [ "$plugin_registered" -gt 0 ]; then
        log_warning "Plugin S3 déjà enregistré dans Storage.pm"
        return 0
    fi
    
    # Ajouter l'import du module
    ssh_exec "sed -i '/^use PVE::Storage::ESXiPlugin;/a use PVE::Storage::Custom::S3Plugin;' /usr/share/perl5/PVE/Storage.pm" ""
    
    # Ajouter l'enregistrement du plugin
    ssh_exec "sed -i '/PVE::Storage::ESXiPlugin->register();/a PVE::Storage::Custom::S3Plugin->register();' /usr/share/perl5/PVE/Storage.pm" ""
    
    log_success "Plugin enregistré dans Storage.pm"
}

# Configuration interactive du provider S3
choose_s3_provider() {
    echo ""
    log_step "Configuration du fournisseur S3"
    echo -e "${CYAN}===========================================${NC}"
    
    echo ""
    echo "Providers S3 supportés :"
    for key in $(echo "${!S3_PROVIDERS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r name endpoint region use_ssl path_style <<< "${S3_PROVIDERS[$key]}"
        echo "  $key. $name"
    done
    
    while true; do
        echo ""
        read -p "👉 Choisissez votre fournisseur S3 (1-8): " provider_choice
        
        if [[ -n "${S3_PROVIDERS[$provider_choice]}" ]]; then
            IFS='|' read -r PROVIDER_NAME ENDPOINT_TEMPLATE DEFAULT_REGION USE_SSL PATH_STYLE <<< "${S3_PROVIDERS[$provider_choice]}"
            log_success "Provider sélectionné : $PROVIDER_NAME"
            break
        else
            log_error "Choix invalide. Veuillez sélectionner un nombre entre 1 et 8."
        fi
    done
}

# Configuration du stockage S3
configure_s3_storage() {
    log_step "Configuration du stockage S3"
    echo -e "${CYAN}===========================================${NC}"
    
    # Choisir le provider
    choose_s3_provider
    
    # Configuration de base
    echo ""
    read -p "📝 ID du stockage [s3-backup]: " STORAGE_ID
    STORAGE_ID=${STORAGE_ID:-s3-backup}
    
    while true; do
        read -p "📦 Nom du bucket S3: " BUCKET_NAME
        if [ -n "$BUCKET_NAME" ]; then
            break
        else
            log_error "Le nom du bucket est obligatoire"
        fi
    done
    
    # Configuration de l'endpoint
    if [[ "$ENDPOINT_TEMPLATE" == *"{custom_endpoint}"* ]]; then
        while true; do
            read -p "🔗 Endpoint personnalisé (ex: minio.example.com:9000): " ENDPOINT
            if [ -n "$ENDPOINT" ]; then
                break
            else
                log_error "L'endpoint est obligatoire pour ce provider"
            fi
        done
        REGION="$DEFAULT_REGION"
    elif [[ "$ENDPOINT_TEMPLATE" == *"{region}"* ]]; then
        read -p "🌍 Région [$DEFAULT_REGION]: " REGION
        REGION=${REGION:-$DEFAULT_REGION}
        ENDPOINT=${ENDPOINT_TEMPLATE//\{region\}/$REGION}
    else
        ENDPOINT="$ENDPOINT_TEMPLATE"
        REGION="$DEFAULT_REGION"
    fi
    
    # Credentials
    while true; do
        read -p "🔑 Access Key ID: " ACCESS_KEY
        if [ -n "$ACCESS_KEY" ]; then
            break
        else
            log_error "L'Access Key est obligatoire"
        fi
    done
    
    while true; do
        read -s -p "🔐 Secret Access Key: " SECRET_KEY
        echo ""
        if [ -n "$SECRET_KEY" ]; then
            break
        else
            log_error "La Secret Key est obligatoire"
        fi
    done
    
    # Préfixe optionnel
    read -p "📂 Préfixe des clés [proxmox/]: " PREFIX
    PREFIX=${PREFIX:-proxmox/}
    if [[ "$PREFIX" != */ ]]; then
        PREFIX="${PREFIX}/"
    fi
    
    # Types de contenu
    echo ""
    echo "📋 Types de contenu supportés :"
    echo "  1. Backups uniquement"
    echo "  2. Backups + ISO"
    echo "  3. Backups + ISO + Templates LXC"
    echo "  4. Tout (Backups + ISO + Templates + Snippets)"
    
    read -p "👉 Choisissez les types de contenu [4]: " content_choice
    case "${content_choice:-4}" in
        1) CONTENT_TYPES="backup" ;;
        2) CONTENT_TYPES="backup,iso" ;;
        3) CONTENT_TYPES="backup,iso,vztmpl" ;;
        4) CONTENT_TYPES="backup,iso,vztmpl,snippets" ;;
        *) CONTENT_TYPES="backup,iso,vztmpl,snippets" ;;
    esac
    
    # Port (déterminé à partir de l'endpoint)
    if [[ "$ENDPOINT" == *":"* ]]; then
        S3_PORT=$(echo "$ENDPOINT" | cut -d':' -f2)
        ENDPOINT_HOST=$(echo "$ENDPOINT" | cut -d':' -f1)
    else
        if [ "$USE_SSL" = "true" ]; then
            S3_PORT="443"
        else
            S3_PORT="80"
        fi
        ENDPOINT_HOST="$ENDPOINT"
    fi
    
    log_success "Configuration S3 terminée"
}

# Génération de la configuration Proxmox
generate_storage_config() {
    log_step "Génération de la configuration Proxmox"
    
    cat > /tmp/s3-storage.cfg << EOF
s3: $STORAGE_ID
    endpoint $ENDPOINT_HOST
    bucket $BUCKET_NAME
    access_key $ACCESS_KEY
    secret_key $SECRET_KEY
    region $REGION
    s3_port $S3_PORT
    use_ssl $([ "$USE_SSL" = "true" ] && echo "1" || echo "0")
    prefix $PREFIX
    content $CONTENT_TYPES
    shared 1
    create_bucket 1
EOF
    
    log_success "Configuration générée dans /tmp/s3-storage.cfg"
}

# Application de la configuration
apply_storage_config() {
    log_step "Application de la configuration S3"
    
    # Copier la configuration temporaire
    scp_copy "/tmp/s3-storage.cfg" "/tmp/s3-storage.cfg" "Copie de la configuration"
    
    # Ajouter la configuration au storage.cfg de Proxmox
    ssh_exec "cat /tmp/s3-storage.cfg >> /etc/pve/storage.cfg" "Ajout de la configuration"
    
    # Nettoyer le fichier temporaire
    ssh_exec "rm -f /tmp/s3-storage.cfg" ""
    rm -f /tmp/s3-storage.cfg
    
    log_success "Configuration S3 appliquée"
}

# Redémarrage des services Proxmox
restart_proxmox_services() {
    log_step "Redémarrage des services Proxmox"
    
    # Redémarrer pvedaemon
    ssh_exec "systemctl restart pvedaemon" "Redémarrage pvedaemon"
    sleep 3
    
    # Redémarrer pveproxy
    ssh_exec "systemctl restart pveproxy" "Redémarrage pveproxy"
    sleep 3
    
    # Vérifier les statuts
    local pvedaemon_status=$(ssh_exec "systemctl is-active pvedaemon" "")
    local pveproxy_status=$(ssh_exec "systemctl is-active pveproxy" "")
    
    if [ "$pvedaemon_status" = "active" ] && [ "$pveproxy_status" = "active" ]; then
        log_success "Services Proxmox redémarrés avec succès"
        return 0
    else
        log_error "Problème lors du redémarrage des services"
        return 1
    fi
}

# Test de la configuration S3
test_s3_configuration() {
    log_step "Test de la configuration S3"
    
    # Tester le statut du stockage
    local storage_status=$(ssh_exec "pvesm status 2>/dev/null | grep '$STORAGE_ID' || echo 'Non trouvé'" "")
    
    if [[ "$storage_status" != *"Non trouvé"* ]]; then
        log_success "Stockage S3 '$STORAGE_ID' détecté dans Proxmox"
        log_info "Status: $storage_status"
        return 0
    else
        log_warning "Stockage S3 non détecté, vérification nécessaire"
        return 1
    fi
}

# Affichage du résumé final
show_final_summary() {
    echo ""
    log_success "Installation terminée avec succès !"
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${WHITE}📋 RÉSUMÉ DE LA CONFIGURATION${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
    echo ""
    echo -e "${CYAN}🎯 Configuration S3 :${NC}"
    echo -e "   Storage ID    : ${WHITE}$STORAGE_ID${NC}"
    echo -e "   Provider      : ${WHITE}$PROVIDER_NAME${NC}"
    echo -e "   Endpoint      : ${WHITE}$ENDPOINT${NC}"
    echo -e "   Bucket        : ${WHITE}$BUCKET_NAME${NC}"
    echo -e "   Region        : ${WHITE}$REGION${NC}"
    echo -e "   Use SSL       : ${WHITE}$USE_SSL${NC}"
    echo -e "   Prefix        : ${WHITE}$PREFIX${NC}"
    echo -e "   Content Types : ${WHITE}$CONTENT_TYPES${NC}"
    echo ""
    echo -e "${CYAN}🌐 Accès Proxmox :${NC}"
    echo -e "   Interface Web : ${WHITE}https://$PROXMOX_HOST:8006${NC}"
    echo -e "   Chemin        : ${WHITE}Datacenter → Storage → $STORAGE_ID${NC}"
    echo ""
    echo -e "${CYAN}🔧 Commandes utiles :${NC}"
    echo -e "   Status        : ${WHITE}pvesm status${NC}"
    echo -e "   Test S3       : ${WHITE}pvesm list $STORAGE_ID${NC}"
    echo -e "   Logs          : ${WHITE}journalctl -u pvedaemon -f${NC}"
    echo ""
    echo -e "${CYAN}📁 Fichiers de sauvegarde :${NC}"
    echo -e "   storage.cfg   : ${WHITE}/etc/pve/storage.cfg.backup_$TIMESTAMP${NC}"
    echo -e "   Storage.pm    : ${WHITE}/usr/share/perl5/PVE/Storage.pm.backup_$TIMESTAMP${NC}"
    echo ""
    log_info "Vous pouvez maintenant utiliser le stockage S3 dans Proxmox !"
}

# Fonction principale
main() {
    # Analyse des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                PROXMOX_HOST="$2"
                shift 2
                ;;
            -u|--user)
                PROXMOX_USER="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 -h PROXMOX_HOST [-u USER] [-k SSH_KEY_PATH]"
                echo ""
                echo "Options:"
                echo "  -h, --host     Adresse IP du serveur Proxmox (obligatoire)"
                echo "  -u, --user     Utilisateur SSH [root]"
                echo "  -k, --key      Chemin vers la clé SSH privée"
                echo "  --help         Affiche cette aide"
                echo ""
                echo "Exemple:"
                echo "  $0 -h 192.168.88.50 -u root"
                echo "  $0 -h 192.168.88.50 -k ~/.ssh/proxmox_key"
                exit 0
                ;;
            *)
                log_error "Option inconnue: $1"
                echo "Utilisez --help pour voir l'aide"
                exit 1
                ;;
        esac
    done
    
    # Vérifier les arguments obligatoires
    if [ -z "$PROXMOX_HOST" ]; then
        log_error "L'adresse du serveur Proxmox est obligatoire"
        echo "Usage: $0 -h PROXMOX_HOST [-u USER] [-k SSH_KEY_PATH]"
        exit 1
    fi
    
    # Exécuter l'installation
    print_header
    
    check_local_environment || exit 1
    test_ssh_connection || exit 1
    check_proxmox_environment || exit 1
    backup_existing_config || exit 1
    install_plugin_files || exit 1
    register_plugin_in_storage || exit 1
    configure_s3_storage || exit 1
    generate_storage_config || exit 1
    apply_storage_config || exit 1
    restart_proxmox_services || exit 1
    test_s3_configuration
    show_final_summary
    
    echo ""
    log_success "🎉 Installation du plugin S3 Proxmox terminée !"
}

# Point d'entrée
main "$@"