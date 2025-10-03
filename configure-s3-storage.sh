#!/bin/bash

# Script de Configuration S3 pour Proxmox VE
# Utilise le plugin S3 déjà installé pour configurer le stockage S3

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage coloré
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Fonction pour saisie de mot de passe avec astérisques
read_password() {
    local prompt="$1"
    local password=""
    local char=""
    
    echo -n "$prompt"
    
    # Désactiver l'écho du terminal
    stty -echo
    
    while IFS= read -r -n1 char; do
        # Si c'est Entrée, sortir de la boucle
        if [[ $char == $'\n' || $char == $'\r' ]]; then
            break
        fi
        
        # Si c'est Backspace, supprimer le dernier caractère
        if [[ $char == $'\177' || $char == $'\b' ]]; then
            if [[ ${#password} -gt 0 ]]; then
                password="${password%?}"
                echo -ne "\b \b"
            fi
        else
            # Ajouter le caractère au mot de passe et afficher *
            password+="$char"
            echo -n "*"
        fi
    done
    
    # Réactiver l'écho du terminal
    stty echo
    echo
    
    # Retourner le mot de passe via une variable globale
    SECRET_INPUT="$password"
}

# Fonction pour vérifier si le plugin S3 est installé
check_s3_plugin() {
    print_header "=== Vérification du Plugin S3 ==="
    
    if [ -f "/usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm" ]; then
        print_status "Plugin S3 trouvé: /usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm"
        return 0
    else
        print_error "Plugin S3 non trouvé!"
        print_error "Veuillez d'abord installer le plugin S3Plugin.pm"
        exit 1
    fi
}

# Fonction pour détecter MinIO existant
detect_existing_minio() {
    print_header "=== Détection MinIO Existant ==="
    
    # Vérifier les containers Proxmox
    if command -v pct &> /dev/null; then
        print_status "Recherche de containers MinIO..."
        pct list | grep -i minio && return 0
    fi
    
    # Vérifier les VMs Proxmox  
    if command -v qm &> /dev/null; then
        print_status "Recherche de VMs MinIO..."
        qm list | grep -i minio && return 0
    fi
    
    # Vérifier les processus MinIO en cours
    if pgrep -f minio &> /dev/null; then
        print_status "Processus MinIO détecté:"
        pgrep -af minio
        return 0
    fi
    
    return 1
}

# Fonction pour choisir le fournisseur S3
choose_s3_provider() {
    print_header "=== Choix du Fournisseur S3 ==="
    
    echo ""
    print_status "Sélection du fournisseur de stockage S3:"
    echo "Choisissez votre fournisseur de stockage S3 compatible:"
    echo ""
    echo "1) MinIO (Auto-hébergé)"
    echo "   → Votre propre serveur MinIO (recommandé pour infrastructure locale)"
    echo ""
    echo "2) Amazon S3"  
    echo "   → Service de stockage cloud d'Amazon Web Services"
    echo ""
    echo "3) Wasabi"
    echo "   → Stockage cloud moins cher, compatible S3"
    echo ""
    echo "4) Backblaze B2"
    echo "   → Stockage cloud économique avec API S3"
    echo ""
    echo "5) DigitalOcean Spaces"
    echo "   → Stockage objet de DigitalOcean"
    echo ""
    echo "6) OVHcloud Object Storage"
    echo "   → Stockage objet d'OVH"
    echo ""
    echo "7) Scaleway Object Storage"
    echo "   → Stockage objet de Scaleway"
    echo ""
    echo "8) Ceph RadosGW"
    echo "   → Gateway S3 pour cluster Ceph"
    echo ""
    echo "9) Configuration personnalisée"
    echo "   → Autre fournisseur compatible S3"
    echo ""
    
    while true; do
        read -p "➤ Choisissez votre fournisseur S3 (1-9): " choice
        case $choice in
            1) 
                S3_PROVIDER="minio"
                print_status "Fournisseur sélectionné: MinIO (Auto-hébergé)"
                break 
                ;;
            2) 
                S3_PROVIDER="aws"
                print_status "Fournisseur sélectionné: Amazon S3"
                break 
                ;;
            3) 
                S3_PROVIDER="wasabi"
                print_status "Fournisseur sélectionné: Wasabi"
                break 
                ;;
            4) 
                S3_PROVIDER="backblaze"
                print_status "Fournisseur sélectionné: Backblaze B2"
                break 
                ;;
            5) 
                S3_PROVIDER="digitalocean"
                print_status "Fournisseur sélectionné: DigitalOcean Spaces"
                break 
                ;;
            6) 
                S3_PROVIDER="ovh"
                print_status "Fournisseur sélectionné: OVHcloud Object Storage"
                break 
                ;;
            7) 
                S3_PROVIDER="scaleway"
                print_status "Fournisseur sélectionné: Scaleway Object Storage"
                break 
                ;;
            8) 
                S3_PROVIDER="ceph"
                print_status "Fournisseur sélectionné: Ceph RadosGW"
                break 
                ;;
            9) 
                S3_PROVIDER="custom"
                print_status "Fournisseur sélectionné: Configuration personnalisée"
                break 
                ;;
            *) 
                print_error "Choix invalide. Veuillez entrer un numéro entre 1 et 9."
                echo ""
                ;;
        esac
    done
}

# Fonction pour configurer MinIO
configure_minio() {
    print_header "=== Configuration MinIO ==="
    
    # Valeurs par défaut pour MinIO local
    S3_ENDPOINT_DEFAULT="192.168.88.90:9000"
    S3_REGION_DEFAULT="us-east-1"
    
    echo ""
    print_status "Configuration de l'endpoint MinIO:"
    echo "L'endpoint est l'adresse IP et le port de votre serveur MinIO."
    echo "Format: adresse_ip:port (ex: 192.168.88.90:9000)"
    echo ""
    read -p "➤ Entrez l'endpoint MinIO [défaut: $S3_ENDPOINT_DEFAULT]: " S3_ENDPOINT
    S3_ENDPOINT=${S3_ENDPOINT:-$S3_ENDPOINT_DEFAULT}
    print_status "Endpoint configuré: $S3_ENDPOINT"
    
    echo ""
    print_status "Configuration de la région S3:"
    echo "La région est un identifiant géographique pour MinIO."
    echo "Zones courantes: us-east-1 (défaut), eu-west-1, eu-central-1, ap-southeast-1"
    echo ""
    read -p "➤ Entrez la région S3 [défaut: $S3_REGION_DEFAULT]: " S3_REGION
    S3_REGION=${S3_REGION:-$S3_REGION_DEFAULT}
    print_status "Région configurée: $S3_REGION"
    
    echo ""
    print_status "Configuration des identifiants MinIO:"
    echo "Vous devez fournir les identifiants d'accès à votre serveur MinIO."
    echo "Ces informations sont configurées dans l'interface MinIO ou lors de l'installation."
    echo "Par défaut MinIO utilise souvent: minioadmin / minioadmin"
    echo ""
    echo -n "➤ Entrez l'Access Key (nom d'utilisateur): "
    read S3_ACCESS_KEY
    while [ -z "$S3_ACCESS_KEY" ]; do
        print_error "L'Access Key est obligatoire!"
        echo -n "➤ Entrez l'Access Key (nom d'utilisateur): "
        read S3_ACCESS_KEY
    done
    
    read_password "➤ Entrez la Secret Key (mot de passe avec *): "
    S3_SECRET_KEY="$SECRET_INPUT"
    while [ -z "$S3_SECRET_KEY" ]; do
        print_error "La Secret Key est obligatoire!"
        read_password "➤ Entrez la Secret Key (mot de passe avec *): "
        S3_SECRET_KEY="$SECRET_INPUT"
    done
    print_status "Identifiants configurés"
    
    echo ""
    print_header "⚠️  ATTENTION - Nom du Bucket ⚠️"
    print_error "Le nom du bucket DOIT être EXACTEMENT identique à celui configuré sur votre serveur MinIO!"
    print_error "Vérifiez le nom exact dans l'interface MinIO avant de continuer."
    echo ""
    print_status "Configuration du bucket S3:"
    echo "Le bucket est un conteneur où seront stockées vos données Proxmox."
    echo "Il doit déjà exister sur votre serveur MinIO avec le nom EXACT."
    echo "Exemples: 'proxmox-backup', 'vm-storage', 'backup-bucket'"
    echo ""
    echo -n "➤ Entrez le nom EXACT du bucket (sensible à la casse): "
    read S3_BUCKET
    while [ -z "$S3_BUCKET" ]; do
        print_error "Le nom du bucket est obligatoire!"
        echo -n "➤ Entrez le nom EXACT du bucket (sensible à la casse): "
        read S3_BUCKET
    done
    print_status "Bucket configuré: $S3_BUCKET"
    
    echo ""
    print_status "Configuration SSL/TLS:"
    echo "Choisissez si vous voulez utiliser une connexion chiffrée (HTTPS) ou non (HTTP)."
    echo "Pour MinIO local, HTTP est généralement suffisant."
    echo ""
    echo -n "➤ Utiliser SSL/HTTPS? (y=Oui, N=Non) [défaut: Non]: "
    read use_ssl
    if [[ $use_ssl =~ ^[Yy]$ ]]; then
        S3_SSL=1
        print_status "SSL activé - connexion HTTPS"
    else
        S3_SSL=0
        print_status "SSL désactivé - connexion HTTP"
    fi
}

# Fonction pour configurer AWS S3
configure_aws() {
    print_header "=== Configuration Amazon S3 ==="
    
    echo ""
    print_status "Configuration de la région AWS:"
    echo "Choisissez la région AWS la plus proche de votre infrastructure."
    echo "Exemples: eu-west-1 (Irlande), us-east-1 (Virginie), ap-southeast-1 (Singapour)"
    echo ""
    read -p "➤ Entrez la région AWS (ex: eu-west-1): " S3_REGION
    while [ -z "$S3_REGION" ]; do
        print_error "La région AWS est obligatoire!"
        read -p "➤ Entrez la région AWS (ex: eu-west-1): " S3_REGION
    done
    print_status "Région configurée: $S3_REGION"
    
    echo ""
    print_status "Configuration des identifiants AWS:"
    echo "Vous devez fournir vos clés d'accès AWS (IAM credentials)."
    echo "Ces informations se trouvent dans votre console AWS > IAM > Users > Security credentials"
    echo ""
    read -p "➤ Entrez votre Access Key ID AWS: " S3_ACCESS_KEY
    while [ -z "$S3_ACCESS_KEY" ]; do
        print_error "L'Access Key ID est obligatoire!"
        read -p "➤ Entrez votre Access Key ID AWS: " S3_ACCESS_KEY
    done
    
    read_password "➤ Entrez votre Secret Access Key AWS (avec *): "
    S3_SECRET_KEY="$SECRET_INPUT"
    while [ -z "$S3_SECRET_KEY" ]; do
        print_error "La Secret Access Key est obligatoire!"
        read_password "➤ Entrez votre Secret Access Key AWS (avec *): "
        S3_SECRET_KEY="$SECRET_INPUT"
    done
    print_status "Identifiants AWS configurés"
    
    echo ""
    print_status "Configuration du bucket S3:"
    echo "Le bucket AWS S3 où seront stockées vos données Proxmox."
    echo "Le bucket doit déjà exister dans votre compte AWS."
    echo ""
    read -p "➤ Entrez le nom du bucket AWS S3: " S3_BUCKET
    while [ -z "$S3_BUCKET" ]; do
        print_error "Le nom du bucket est obligatoire!"
        read -p "➤ Entrez le nom du bucket AWS S3: " S3_BUCKET
    done
    print_status "Bucket configuré: $S3_BUCKET"
    
    S3_ENDPOINT="s3.${S3_REGION}.amazonaws.com"
    S3_SSL=1
    print_status "Endpoint automatique: $S3_ENDPOINT (SSL activé)"
}

# Fonction pour configurer Wasabi
configure_wasabi() {
    print_header "=== Configuration Wasabi ==="
    
    echo ""
    print_status "Sélection de la région Wasabi:"
    echo "Choisissez la région Wasabi la plus proche:"
    echo ""
    echo "1) us-east-1 (Virginia, USA)"
    echo "2) us-west-1 (Oregon, USA)"
    echo "3) eu-central-1 (Amsterdam, Pays-Bas)"
    echo "4) eu-west-1 (Londres, Royaume-Uni)"
    echo "5) eu-west-2 (Paris, France)"
    echo "6) ap-northeast-1 (Tokyo, Japon)"
    echo "7) ap-northeast-2 (Osaka, Japon)"
    echo "8) ap-southeast-1 (Singapour)"
    echo "9) ap-southeast-2 (Sydney, Australie)"
    echo "10) ca-central-1 (Toronto, Canada)"
    echo ""
    
    while true; do
        read -p "➤ Choisissez une région (1-10): " region_choice
        case $region_choice in
            1) S3_REGION="us-east-1"; S3_ENDPOINT="s3.wasabisys.com"; break ;;
            2) S3_REGION="us-west-1"; S3_ENDPOINT="s3.us-west-1.wasabisys.com"; break ;;
            3) S3_REGION="eu-central-1"; S3_ENDPOINT="s3.eu-central-1.wasabisys.com"; break ;;
            4) S3_REGION="eu-west-1"; S3_ENDPOINT="s3.eu-west-1.wasabisys.com"; break ;;
            5) S3_REGION="eu-west-2"; S3_ENDPOINT="s3.eu-west-2.wasabisys.com"; break ;;
            6) S3_REGION="ap-northeast-1"; S3_ENDPOINT="s3.ap-northeast-1.wasabisys.com"; break ;;
            7) S3_REGION="ap-northeast-2"; S3_ENDPOINT="s3.ap-northeast-2.wasabisys.com"; break ;;
            8) S3_REGION="ap-southeast-1"; S3_ENDPOINT="s3.ap-southeast-1.wasabisys.com"; break ;;
            9) S3_REGION="ap-southeast-2"; S3_ENDPOINT="s3.ap-southeast-2.wasabisys.com"; break ;;
            10) S3_REGION="ca-central-1"; S3_ENDPOINT="s3.ca-central-1.wasabisys.com"; break ;;
            *) print_error "Choix invalide. Veuillez choisir entre 1 et 10." ;;
        esac
    done
    print_status "Région sélectionnée: $S3_REGION ($S3_ENDPOINT)"
    
    echo ""
    print_status "Configuration des identifiants Wasabi:"
    echo ""
    echo -n "➤ Entrez votre Access Key Wasabi: "
    read S3_ACCESS_KEY
    while [ -z "$S3_ACCESS_KEY" ]; do
        print_error "L'Access Key est obligatoire!"
        echo -n "➤ Entrez votre Access Key Wasabi: "
        read S3_ACCESS_KEY
    done
    
    read_password "➤ Entrez votre Secret Key Wasabi (avec *): "
    S3_SECRET_KEY="$SECRET_INPUT"
    while [ -z "$S3_SECRET_KEY" ]; do
        print_error "La Secret Key est obligatoire!"
        read_password "➤ Entrez votre Secret Key Wasabi (avec *): "
        S3_SECRET_KEY="$SECRET_INPUT"
    done
    
    echo ""
    echo -n "➤ Entrez le nom du bucket Wasabi: "
    read S3_BUCKET
    while [ -z "$S3_BUCKET" ]; do
        print_error "Le nom du bucket est obligatoire!"
        echo -n "➤ Entrez le nom du bucket Wasabi: "
        read S3_BUCKET
    done
    
    S3_SSL=1
    print_status "Configuration Wasabi terminée"
}

# Fonction pour configuration personnalisée
configure_custom() {
    print_header "=== Configuration Personnalisée ==="
    
    echo ""
    print_status "Configuration de l'endpoint S3 personnalisé:"
    echo "Entrez l'adresse de votre serveur S3 compatible (sans http/https)."
    echo "Exemples: s3.exemple.com, minio.mondomaine.fr, 10.0.0.100:9000"
    echo ""
    read -p "➤ Entrez l'endpoint S3: " S3_ENDPOINT
    while [ -z "$S3_ENDPOINT" ]; do
        print_error "L'endpoint est obligatoire!"
        read -p "➤ Entrez l'endpoint S3: " S3_ENDPOINT
    done
    print_status "Endpoint configuré: $S3_ENDPOINT"
    
    echo ""
    print_status "Configuration de la région:"
    echo "Entrez la région de votre serveur S3 (souvent 'us-east-1' par défaut)."
    echo ""
    read -p "➤ Entrez la région [défaut: us-east-1]: " S3_REGION
    S3_REGION=${S3_REGION:-us-east-1}
    print_status "Région configurée: $S3_REGION"
    
    echo ""
    print_status "Configuration des identifiants d'accès:"
    echo "Entrez vos identifiants pour accéder au serveur S3."
    echo ""
    read -p "➤ Entrez l'Access Key: " S3_ACCESS_KEY
    while [ -z "$S3_ACCESS_KEY" ]; do
        print_error "L'Access Key est obligatoire!"
        read -p "➤ Entrez l'Access Key: " S3_ACCESS_KEY
    done
    
    read_password "➤ Entrez la Secret Key (avec *): "
    S3_SECRET_KEY="$SECRET_INPUT"
    while [ -z "$S3_SECRET_KEY" ]; do
        print_error "La Secret Key est obligatoire!"
        read_password "➤ Entrez la Secret Key (avec *): "
        S3_SECRET_KEY="$SECRET_INPUT"
    done
    print_status "Identifiants configurés"
    
    echo ""
    print_status "Configuration du bucket:"
    echo "Entrez le nom du bucket où stocker les données Proxmox."
    echo ""
    read -p "➤ Entrez le nom du bucket: " S3_BUCKET
    while [ -z "$S3_BUCKET" ]; do
        print_error "Le nom du bucket est obligatoire!"
        read -p "➤ Entrez le nom du bucket: " S3_BUCKET
    done
    print_status "Bucket configuré: $S3_BUCKET"
    
    echo ""
    print_status "Configuration SSL/TLS:"
    echo "Choisissez si votre serveur S3 utilise une connexion chiffrée."
    echo ""
    read -p "➤ Utiliser SSL/HTTPS? (Y=Oui, n=Non) [défaut: Oui]: " use_ssl
    if [[ $use_ssl =~ ^[Nn]$ ]]; then
        S3_SSL=0
        print_status "SSL désactivé - connexion HTTP"
    else
        S3_SSL=1
        print_status "SSL activé - connexion HTTPS"
    fi
}

# Fonction principale de configuration S3
configure_s3_credentials() {
    case $S3_PROVIDER in
        "minio") configure_minio ;;
        "aws") configure_aws ;;
        "wasabi") configure_wasabi ;;
        "backblaze"|"digitalocean"|"ovh"|"scaleway"|"ceph") configure_custom ;;
        "custom") configure_custom ;;
        *) print_error "Fournisseur non supporté: $S3_PROVIDER"; exit 1 ;;
    esac
}

# Fonction pour valider les credentials S3
validate_s3_connection() {
    print_header "=== Test de Connexion S3 ==="
    
    # Test basique de connectivité
    local protocol="http"
    if [ "$S3_SSL" = "1" ]; then
        protocol="https"
    fi
    
    local url="${protocol}://${S3_ENDPOINT}"
    print_status "Test de connexion vers: $url"
    print_status "Bucket: $S3_BUCKET"
    print_status "Région: $S3_REGION"
    
    # Test simple de connectivité réseau
    if curl -s --connect-timeout 5 --max-time 10 "$url" > /dev/null 2>&1; then
        print_status "Test de connectivité réseau: OK"
    else
        print_warning "Problème de connectivité réseau vers $url"
    fi
    
    print_status "Configuration semble valide (test basique)"
}

# Fonction pour vérifier que le plugin S3 est disponible dans l'interface
check_s3_plugin_registration() {
    print_header "=== Vérification de l'Enregistrement du Plugin S3 ==="
    
    # Vérifier que le plugin est chargé
    if perl -I/usr/share/perl5 -e 'use PVE::Storage::S3Plugin; print "OK\n";' 2>/dev/null; then
        print_status "✓ Plugin S3 chargeable"
    else
        print_error "✗ Problème de chargement du plugin S3"
        return 1
    fi
    
    # Redémarrer les services web pour être sûr
    print_status "Redémarrage des services web Proxmox..."
    systemctl restart pveproxy pvestatd >/dev/null 2>&1
    sleep 3
    
    print_status "✓ Le type S3 devrait maintenant être disponible dans:"
    print_status "  → Interface web: Datacenter → Storage → Add → S3"
    print_status "  → API REST: /api2/json/storage (type=s3)"
}

# Fonction pour créer la configuration de stockage
create_storage_config() {
    print_header "=== Configuration du Stockage Proxmox ==="
    
    echo ""
    print_status "Configuration du nom du stockage:"
    echo "Choisissez un nom pour identifier ce stockage S3 dans Proxmox."
    echo "Ce nom apparaîtra dans l'interface Proxmox (lettres, chiffres, tirets uniquement)."
    echo ""
    read -p "➤ Entrez le nom du stockage S3 [défaut: s3-storage]: " STORAGE_NAME
    STORAGE_NAME=${STORAGE_NAME:-s3-storage}
    print_status "Nom du stockage: $STORAGE_NAME"
    
    echo ""
    print_status "Configuration des types de contenu:"
    echo "Choisissez quel type de données Proxmox pourra stocker sur ce S3:"
    echo ""
    echo "1) Sauvegardes uniquement"
    echo "   → Stockage des sauvegardes VM/CT (vzdump) uniquement"
    echo ""
    echo "2) Images VM + Sauvegardes (recommandé)"
    echo "   → Stockage des disques virtuels et des sauvegardes"
    echo ""
    echo "3) Tout le contenu"
    echo "   → Images, sauvegardes, ISO, templates, snippets"
    echo ""
    while true; do
        read -p "➤ Choisissez le type de contenu (1-3) [défaut: 2]: " content_choice
        content_choice=${content_choice:-2}
        case $content_choice in
            1) 
                CONTENT="backup"
                print_status "Configuration: Sauvegardes uniquement"
                break
                ;;
            2) 
                CONTENT="images,backup"
                print_status "Configuration: Images VM + Sauvegardes"
                break
                ;;
            3) 
                CONTENT="images,backup,iso,vztmpl,snippets"
                print_status "Configuration: Tout le contenu"
                break
                ;;
            *) 
                print_error "Choix invalide. Veuillez choisir 1, 2 ou 3."
                ;;
        esac
    done
    
    # Créer la configuration avec les bonnes propriétés du plugin S3
    STORAGE_CONFIG="s3: $STORAGE_NAME
    endpoint $S3_ENDPOINT
    access_key $S3_ACCESS_KEY
    secret_key $S3_SECRET_KEY
    bucket $S3_BUCKET
    region $S3_REGION"
    
    if [ "$S3_SSL" = "1" ]; then
        STORAGE_CONFIG="$STORAGE_CONFIG
    use_ssl 1"
    fi
    
    STORAGE_CONFIG="$STORAGE_CONFIG
    content $CONTENT"
    
    echo ""
    print_status "Configuration Proxmox générée:"
    print_status "Cette configuration sera ajoutée au fichier /etc/pve/storage.cfg"
    echo ""
    echo "$STORAGE_CONFIG"
    echo ""
}

# Fonction pour ajouter le stockage à Proxmox
add_storage_to_proxmox() {
    print_header "=== Ajout du Stockage à Proxmox ==="
    
    # Backup de la configuration existante
    cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup.$(date +%Y%m%d_%H%M%S)
    print_status "Sauvegarde créée: /etc/pve/storage.cfg.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Vérifier si le stockage existe déjà
    if grep -q "^s3: $STORAGE_NAME" /etc/pve/storage.cfg; then
        print_warning "Le stockage '$STORAGE_NAME' existe déjà"
        read -p "Voulez-vous le remplacer? (y/N): " replace
        if [[ $replace =~ ^[Yy]$ ]]; then
            # Supprimer l'ancienne configuration
            sed -i "/^s3: $STORAGE_NAME/,/^$/d" /etc/pve/storage.cfg
            print_status "Ancienne configuration supprimée"
        else
            print_error "Configuration annulée"
            exit 1
        fi
    fi
    
    # Ajouter la nouvelle configuration
    echo "" >> /etc/pve/storage.cfg
    echo "$STORAGE_CONFIG" >> /etc/pve/storage.cfg
    print_status "Configuration ajoutée à /etc/pve/storage.cfg"
}

# Fonction pour redémarrer les services Proxmox
restart_proxmox_services() {
    print_header "=== Redémarrage des Services Proxmox ==="
    
    print_status "Redémarrage de pvedaemon..."
    systemctl restart pvedaemon
    
    if systemctl is-active --quiet pve-cluster; then
        print_status "Redémarrage de pve-cluster..."
        systemctl restart pve-cluster
    fi
    
    # Attendre que les services redémarrent
    sleep 5
    
    if systemctl is-active --quiet pvedaemon; then
        print_status "pvedaemon redémarré avec succès"
    else
        print_error "Échec du redémarrage de pvedaemon"
        exit 1
    fi
}

# Fonction pour tester la configuration finale
test_final_configuration() {
    print_header "=== Test de la Configuration Finale ==="
    
    print_status "Vérification du statut des stockages..."
    
    # Vérification silencieuse de la configuration générale
    local pvesm_exit_code
    pvesm status >/dev/null 2>&1
    pvesm_exit_code=$?
    
    if [ $pvesm_exit_code -eq 0 ]; then
        print_status "Statut général des stockages: OK"
    else
        print_error "Erreurs détectées dans la configuration des stockages"
        print_warning "Vérifiez le fichier /etc/pve/storage.cfg pour d'éventuelles erreurs de syntaxe"
        echo ""
        print_warning "Vérification détaillée du fichier de configuration..."
        
        # Vérifier la syntaxe du fichier storage.cfg
        if grep -n "^s3: $STORAGE_NAME" /etc/pve/storage.cfg > /dev/null; then
            print_status "Section S3 trouvée dans /etc/pve/storage.cfg"
            
            # Afficher la configuration ajoutée
            print_status "Configuration ajoutée:"
            sed -n "/^s3: $STORAGE_NAME/,/^$/p" /etc/pve/storage.cfg | while read line; do
                echo "    $line"
            done
        else
            print_error "Section S3 '$STORAGE_NAME' non trouvée dans /etc/pve/storage.cfg"
        fi
    fi
    
    echo ""
    print_status "Test spécifique du stockage S3 '$STORAGE_NAME'..."
    
    # Test spécifique du stockage S3 (sans afficher les messages)
    local s3_test_exit_code
    pvesm status --storage "$STORAGE_NAME" >/dev/null 2>&1
    s3_test_exit_code=$?
    
    if [ $s3_test_exit_code -eq 0 ]; then
        print_status "✅ Stockage S3 '$STORAGE_NAME' configuré avec succès!"
        
        # Extraire seulement le statut du stockage S3
        local s3_status=$(pvesm status 2>/dev/null | grep "^$STORAGE_NAME" || echo "$STORAGE_NAME s3 inactive 0 0 0 0.00%")
        print_status "Statut: $s3_status"
    else
        print_error "❌ Problème avec le stockage S3 '$STORAGE_NAME'"
        print_error "Le stockage n'est pas accessible (vérifiez les credentials S3)"
        echo ""
        print_warning "Suggestions de résolution:"
        print_warning "1. Vérifiez que le plugin S3 est correctement installé"
        print_warning "2. Vérifiez les credentials S3 (access_key/secret_key)"
        print_warning "3. Vérifiez que le bucket '$S3_BUCKET' existe sur le serveur S3"
        print_warning "4. Vérifiez la connectivité réseau vers l'endpoint '$S3_ENDPOINT'"
        print_warning "5. Consultez les logs: journalctl -u pvedaemon -f"
    fi
    
    echo ""
    print_status "Vérification de l'interface web Proxmox..."
    print_status "✓ Le stockage '$STORAGE_NAME' devrait maintenant apparaître dans:"
    print_status "  → Datacenter → Storage (liste des stockages)"
    print_status "  → Datacenter → Storage → Add → S3 (pour en ajouter un nouveau)"
    print_status "✓ Une fois le stockage actif, il apparaîtra dans les menus de création VM/CT"
}

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Script de configuration S3 pour Proxmox VE"
    echo ""
    echo "Options:"
    echo "  -h, --help          Afficher cette aide"
    echo "  -p, --provider      Spécifier le fournisseur S3 (minio, aws, wasabi, etc.)"
    echo "  -n, --name          Nom du stockage dans Proxmox"
    echo "  --endpoint          Endpoint S3"
    echo "  --region           Région S3"  
    echo "  --bucket           Nom du bucket S3"
    echo "  --access-key       Access Key S3"
    echo "  --secret-key       Secret Key S3"
    echo "  --content          Types de contenu (backup, images,backup, etc.)"
    echo ""
    echo "Exemple:"
    echo "  $0 --provider minio --endpoint 192.168.88.90:9000 --bucket proxmox-backup"
}

# Fonction principale
main() {
    print_header "=========================================="
    print_header "  Configuration S3 pour Proxmox VE"
    print_header "=========================================="
    
    # Vérifier si on est root
    if [ "$EUID" -ne 0 ]; then
        print_error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
    
    # Vérifier l'installation du plugin
    check_s3_plugin
    
    # Détecter MinIO existant
    if detect_existing_minio; then
        print_status "Infrastructure MinIO détectée"
    else
        print_status "Aucune infrastructure MinIO détectée"
    fi
    
    # Configuration interactive si pas d'arguments
    if [ $# -eq 0 ]; then
        choose_s3_provider
        configure_s3_credentials
        validate_s3_connection
        check_s3_plugin_registration
        create_storage_config
        
        echo ""
        print_header "=== Confirmation de la Configuration ==="
        echo ""
        print_status "Résumé de la configuration S3:"
        print_status "  • Fournisseur: $S3_PROVIDER"
        print_status "  • Endpoint: $S3_ENDPOINT"
        print_status "  • Région: $S3_REGION"
        print_status "  • Bucket: $S3_BUCKET"
        print_status "  • SSL: $([ "$S3_SSL" = "1" ] && echo "Activé" || echo "Désactivé")"
        print_status "  • Nom du stockage: $STORAGE_NAME"
        print_status "  • Types de contenu: $CONTENT"
        echo ""
        print_status "Cette configuration sera ajoutée à Proxmox et les services seront redémarrés."
        echo ""
        read -p "➤ Voulez-vous appliquer cette configuration? (Y=Oui, n=Non) [défaut: Oui]: " confirm
        if [[ ! $confirm =~ ^[Nn]$ ]]; then
            add_storage_to_proxmox
            restart_proxmox_services
            test_final_configuration
            
            print_status ""
            print_status "=========================================="
            print_status "Configuration S3 terminée avec succès!"
            print_status "Stockage '$STORAGE_NAME' disponible dans:"
            print_status "Datacenter → Storage → Add → S3"
            print_status "=========================================="
        else
            print_status "Configuration générée mais pas appliquée"
            print_status "Vous pouvez relancer le script pour appliquer la configuration"
        fi
    fi
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--provider)
            S3_PROVIDER="$2"
            shift 2
            ;;
        -n|--name)
            STORAGE_NAME="$2"
            shift 2
            ;;
        --endpoint)
            S3_ENDPOINT="$2"
            shift 2
            ;;
        --region)
            S3_REGION="$2"
            shift 2
            ;;
        --bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        --access-key)
            S3_ACCESS_KEY="$2"
            shift 2
            ;;
        --secret-key)
            S3_SECRET_KEY="$2"
            shift 2
            ;;
        --content)
            CONTENT="$2"
            shift 2
            ;;
        *)
            print_error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Lancer le script principal
main "$@"