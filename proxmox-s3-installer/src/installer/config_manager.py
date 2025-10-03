from utils.validation import (
    validate_storage_name, validate_s3_bucket_name, validate_s3_prefix,
    validate_access_key, validate_secret_key,
    get_storage_name_examples, get_bucket_name_examples, get_prefix_examples
)

class ConfigManager:
    def __init__(self):
        self.config = {}

    def prompt_with_validation(self, prompt_text, validator, examples=None):
        """Prompt avec validation et exemples"""
        if examples:
            print(f"\nExemples: {', '.join(examples)}")
        
        while True:
            value = input(prompt_text)
            is_valid, message = validator(value)
            if is_valid:
                print(f"✓ {message}")
                return value
            else:
                print(f"✗ Erreur: {message}")
                print("Veuillez réessayer.")

    def prompt_for_configuration(self):
        print("\n" + "="*60)
        print("   Configuration du stockage S3 pour Proxmox VE")
        print("="*60)
        
        # Nom de stockage
        print("\n1. Nom de stockage Proxmox")
        print("   Le nom apparaîtra dans l'interface Proxmox sous 'Datacenter > Storage'")
        self.config['storage_name'] = self.prompt_with_validation(
            "Entrez le nom de stockage: ",
            validate_storage_name,
            get_storage_name_examples()
        )
        
        # Nom du bucket S3
        print("\n2. Bucket S3")
        print("   Le bucket doit déjà exister dans votre service S3")
        self.config['bucket'] = self.prompt_with_validation(
            "Entrez le nom du bucket S3: ",
            validate_s3_bucket_name,
            get_bucket_name_examples()
        )
        
        # Endpoint
        print("\n3. Endpoint S3")
        self.config['endpoint'] = self.choose_endpoint()
        
        # Région avec suggestions européennes
        print("\n4. Région")
        endpoint = self.config.get('endpoint', '')
        
        if 'amazonaws.com' in endpoint:
            print("   Régions AWS populaires:")
            print("   🇪🇺 Europe: eu-west-1 (Irlande), eu-central-1 (Francfort), eu-west-3 (Paris)")
            print("   🇺🇸 US: us-east-1 (Virginie), us-west-2 (Oregon)")
            print("   🌏 Asie: ap-southeast-1 (Singapour), ap-northeast-1 (Tokyo)")
            default_region = "eu-west-1"
        elif 'scaleway' in endpoint.lower() or 'scw.cloud' in endpoint:
            print("   Régions Scaleway: fr-par (Paris), nl-ams (Amsterdam), pl-waw (Varsovie)")
            default_region = "fr-par"
        elif 'ovh' in endpoint.lower():
            print("   Régions OVH: gra (Gravelines), sbg (Strasbourg), uk (Londres)")
            default_region = "gra"
        else:
            print("   Exemples: us-east-1, eu-west-1, eu-central-1")
            default_region = "us-east-1"
            
        region_input = input(f"Entrez la région (défaut: {default_region}): ").strip()
        self.config['region'] = region_input or default_region
        
        # Clé d'accès avec instructions claires
        print("\n5. Authentification S3 - Clé d'accès")
        endpoint = self.config.get('endpoint', '')
        
        if 'amazonaws.com' in endpoint:
            print("   📋 AWS S3 - ACCESS KEY ID:")
            print("      • Format: commence par 'AKIA' (20 caractères total)")
            print("      • Trouvez-la dans: AWS Console > IAM > Users > Security credentials")
            examples = ["AKIAIOSFODNN7EXAMPLE"]
        elif 'minio' in endpoint.lower():
            print("   📋 MinIO - ACCESS KEY (nom d'utilisateur):")
            print("      • C'est le nom d'utilisateur de votre compte MinIO")
            print("      • Par défaut: 'minioadmin' (modifiable dans MinIO)")
            print("      • Trouvez-le dans: MinIO Console > Identity > Users")
            examples = ["minioadmin", "backup-user", "s3-admin"]
        elif 'scaleway' in endpoint.lower():
            print("   📋 Scaleway - ACCESS KEY:")
            print("      • Clé d'accès Scaleway (format: SCW...)")
            print("      • Trouvez-la dans: Console Scaleway > Credentials > API Keys")
            examples = ["SCW12345ABCDEF", "access-key-scaleway"]
        else:
            print("   📋 Service S3 - ACCESS KEY:")
            print("      • Nom d'utilisateur ou clé d'accès fourni par votre service")
            print("      • Consultez la documentation de votre fournisseur S3")
            examples = ["admin", "s3user", "backup-access"]
            
        print(f"   💡 Exemples: {', '.join(examples)}")
        self.config['access_key'] = self.prompt_with_validation(
            "🔑 Entrez votre clé d'accès S3: ",
            validate_access_key
        )
        
        # Clé secrète avec instructions claires
        print("\n6. Authentification S3 - Clé secrète")
        if 'amazonaws.com' in endpoint:
            print("   📋 AWS S3 - SECRET ACCESS KEY:")
            print("      • Format: 40 caractères alphanumériques avec +/")
            print("      • ⚠️  Visible uniquement lors de la création!")
            print("      • Trouvez-la dans: AWS Console > IAM > Users > Security credentials")
            examples = ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY (40 car.)"]
        elif 'minio' in endpoint.lower():
            print("   📋 MinIO - SECRET KEY (mot de passe):")
            print("      • C'est le mot de passe de votre compte MinIO")
            print("      • Par défaut: 'minioadmin' (CHANGEZ-LE en production!)")
            print("      • Trouvez-le dans: MinIO Console > Identity > Users")
            examples = ["minioadmin", "SecurePassword123!", "MinIO-P@ssw0rd"]
        elif 'scaleway' in endpoint.lower():
            print("   📋 Scaleway - SECRET KEY:")
            print("      • Clé secrète associée à votre clé d'accès")
            print("      • ⚠️  Visible uniquement lors de la création!")
            examples = ["12345678-90ab-cdef-1234-567890abcdef"]
        else:
            print("   📋 Service S3 - SECRET KEY:")
            print("      • Mot de passe ou clé secrète associée à votre clé d'accès")
            print("      • Consultez la documentation de votre fournisseur S3")
            examples = ["SecretPassword123", "my-secret-key-456"]
            
        print(f"   💡 Exemples: {', '.join(examples)}")
        self.config['secret_key'] = self.prompt_with_validation(
            "🔐 Entrez votre clé secrète S3: ",
            validate_secret_key
        )
        
        # Préfixe
        print("\n7. Préfixe (optionnel)")
        print("   Dossier virtuel dans le bucket pour organiser les fichiers")
        self.config['prefix'] = self.prompt_with_validation(
            "Entrez le préfixe (appuyez sur Entrée pour aucun): ",
            validate_s3_prefix,
            get_prefix_examples()
        )
        
        # Configuration par défaut pour les autres paramètres
        print("\n8. Configuration des types de contenu")
        content_options = ["backup", "backup,iso", "backup,iso,vztmpl", "backup,iso,vztmpl,snippets"]
        print("Options disponibles:")
        for i, option in enumerate(content_options, 1):
            print(f"   {i}. {option}")
        
        content_choice = input("Choisissez une option (1-4) ou tapez votre configuration: ").strip()
        try:
            choice_idx = int(content_choice) - 1
            if 0 <= choice_idx < len(content_options):
                self.config['content'] = content_options[choice_idx]
            else:
                raise ValueError()
        except ValueError:
            self.config['content'] = content_choice or "backup,iso,vztmpl,snippets"
        
        # Paramètres de performance
        print("\n9. Paramètres de performance")
        print("   Taille des chunks multipart (5-5120 MB, défaut: 100)")
        chunk_size = input("Taille des chunks (MB): ").strip()
        self.config['multipart_chunk_size'] = chunk_size or "100"
        
        print("   Nombre d'uploads simultanés (1-20, défaut: 3)")
        concurrent_uploads = input("Uploads simultanés: ").strip()
        self.config['max_concurrent_uploads'] = concurrent_uploads or "3"
        
        # Classe de stockage
        print("\n10. Classe de stockage")
        storage_classes = ["STANDARD", "STANDARD_IA", "REDUCED_REDUNDANCY", "GLACIER"]
        print("Classes disponibles:", ", ".join(storage_classes))
        storage_class = input("Classe de stockage (défaut: STANDARD): ").strip()
        self.config['storage_class'] = storage_class.upper() if storage_class else "STANDARD"

    def choose_endpoint(self):
        endpoints = [
            {"name": "AWS S3", "endpoint": "s3.amazonaws.com", "default_region": "us-east-1"},
            {"name": "MinIO", "endpoint": "minio.example.com:9000", "default_region": "us-east-1"},
            {"name": "Ceph RadosGW", "endpoint": "ceph-rgw.example.com:7480", "default_region": "default"},
            {"name": "Wasabi", "endpoint": "s3.wasabisys.com", "default_region": "us-east-1"},
            {"name": "Scaleway Object Storage", "endpoint": "s3.fr-par.scw.cloud", "default_region": "fr-par"},
            {"name": "DigitalOcean Spaces", "endpoint": "fra1.digitaloceanspaces.com", "default_region": "fra1"},
            {"name": "Linode Object Storage", "endpoint": "eu-central-1.linodeobjects.com", "default_region": "eu-central-1"},
            {"name": "Autre (personnalisé)", "endpoint": "", "default_region": "us-east-1"}
        ]
        
        print("Choisissez votre fournisseur S3:")
        for i, ep in enumerate(endpoints, 1):
            print(f"   {i}. {ep['name']}")
            if ep['endpoint']:
                print(f"      Endpoint: {ep['endpoint']}")
        
        while True:
            try:
                choice = int(input("Votre choix (1-{}): ".format(len(endpoints))))
                if 1 <= choice <= len(endpoints):
                    selected = endpoints[choice - 1]
                    
                    if selected['name'] == "Autre (personnalisé)":
                        endpoint = input("Entrez votre endpoint personnalisé: ").strip()
                        while not endpoint:
                            print("L'endpoint ne peut pas être vide.")
                            endpoint = input("Entrez votre endpoint personnalisé: ").strip()
                        return endpoint
                    else:
                        # Mise à jour automatique de la région par défaut
                        if 'region' not in self.config:
                            self.config['default_region'] = selected['default_region']
                        return selected['endpoint']
                else:
                    print(f"Veuillez entrer un nombre entre 1 et {len(endpoints)}")
            except ValueError:
                print("Veuillez entrer un nombre valide")

    def create_storage_config(self):
        # Construction de la configuration en fonction des paramètres
        config_lines = [
            f"s3: {self.config['storage_name']}",
            f"    bucket {self.config['bucket']}",
            f"    endpoint {self.config['endpoint']}",
            f"    region {self.config['region']}",
            f"    access_key {self.config['access_key']}",
            f"    secret_key {self.config['secret_key']}"
        ]
        
        # Ajouter le préfixe seulement s'il n'est pas vide
        if self.config['prefix'].strip():
            config_lines.append(f"    prefix {self.config['prefix']}")
            
        config_lines.extend([
            f"    content {self.config['content']}",
            f"    storage_class {self.config['storage_class']}",
            f"    multipart_chunk_size {self.config['multipart_chunk_size']}",
            f"    max_concurrent_uploads {self.config['max_concurrent_uploads']}"
        ])
        
        config_content = "\n".join(config_lines)
        
        print(f"\n📝 Écriture de la configuration dans /etc/pve/storage.cfg...")
        print("\nConfiguration générée:")
        print("-" * 40)
        print(config_content)
        print("-" * 40)
        
        try:
            with open('/etc/pve/storage.cfg', 'w') as config_file:
                config_file.write(config_content)
            print("✓ Configuration écrite avec succès")
        except PermissionError:
            print("✗ Erreur: Permission refusée pour écrire dans /etc/pve/storage.cfg")
            print("  Assurez-vous d'exécuter le script avec les privilèges administrateur")
        except Exception as e:
            print(f"✗ Erreur lors de l'écriture: {e}")

    def show_config_preview(self):
        """Affiche un aperçu de la configuration sans l'écrire"""
        config_lines = [
            f"s3: {self.config['storage_name']}",
            f"    bucket {self.config['bucket']}",
            f"    endpoint {self.config['endpoint']}",
            f"    region {self.config['region']}",
            f"    access_key {self.config['access_key']}",
            f"    secret_key {self.config['secret_key']}"
        ]
        
        # Ajouter le préfixe seulement s'il n'est pas vide
        if self.config['prefix'].strip():
            config_lines.append(f"    prefix {self.config['prefix']}")
            
        config_lines.extend([
            f"    content {self.config['content']}",
            f"    storage_class {self.config['storage_class']}",
            f"    multipart_chunk_size {self.config['multipart_chunk_size']}",
            f"    max_concurrent_uploads {self.config['max_concurrent_uploads']}"
        ])
        
        config_content = "\n".join(config_lines)
        
        print("┌" + "─" * 58 + "┐")
        print("│" + " " * 58 + "│")
        for line in config_content.split('\n'):
            print(f"│ {line:<56} │")
        print("│" + " " * 58 + "│")
        print("└" + "─" * 58 + "┘")
        print()
        print("✓ Configuration preview generated successfully")

    def display_information(self):
        print("\n" + "="*60)
        print("   CONFIGURATION TERMINÉE AVEC SUCCÈS")
        print("="*60)
        
        print(f"\n✓ Stockage '{self.config['storage_name']}' configuré")
        print(f"✓ Bucket S3: {self.config['bucket']}")
        print(f"✓ Endpoint: {self.config['endpoint']}")
        print(f"✓ Région: {self.config['region']}")
        
        print("\n" + "="*60)
        print("   INTERFACE WEB PROXMOX")
        print("="*60)
        print("Le stockage S3 est maintenant disponible dans:")
        print("  → Interface Proxmox > Datacenter > Storage")
        print("  → Nom du stockage: '{}'".format(self.config['storage_name']))
        print("  → Types de contenu: {}".format(self.config['content']))
        
        print("\n" + "="*60)
        print("   LIGNES DE COMMANDE")
        print("="*60)
        storage_name = self.config['storage_name']
        
        print("📦 SAUVEGARDE MANUELLE:")
        print(f"   pve-s3-backup --storage {storage_name} --source /var/lib/vz/dump/vzdump-qemu-100-*.vma.gz --vmid 100")
        
        print("\n📋 LISTER LES SAUVEGARDES:")
        print(f"   pve-s3-restore --storage {storage_name} --list")
        print(f"   pve-s3-restore --storage {storage_name} --list --vmid 100")
        
        print("\n📥 RESTAURATION:")
        print(f"   pve-s3-restore --storage {storage_name} --source nom-backup.vma.gz --destination /tmp/")
        
        print("\n🔧 MAINTENANCE:")
        print(f"   pve-s3-maintenance --storage {storage_name} --action status")
        print(f"   pve-s3-maintenance --storage {storage_name} --action cleanup --older-than 90d")
        print(f"   pve-s3-maintenance --storage {storage_name} --action check-integrity")
        
        print("\n" + "="*60)
        print("   FICHIERS DE CONFIGURATION")
        print("="*60)
        print("Configuration principale:")
        print("  → /etc/pve/storage.cfg")
        print("\nCredentials (sécurisés):")
        print("  → /etc/pve/s3-credentials/aws-credentials")
        print("\nLogs:")
        print("  → /var/log/pve/storage-s3.log")
        
        print("\n" + "="*60)
        print("   VÉRIFICATION ET DÉPANNAGE")
        print("="*60)
        print("🔍 Si le stockage ne s'affiche PAS dans Proxmox:")
        print()
        print("1️⃣ REDÉMARREZ le service Proxmox:")
        print("   systemctl restart pvedaemon")
        print("   systemctl restart pveproxy")
        print()
        print("2️⃣ VÉRIFIEZ les logs d'erreur:")
        print("   journalctl -u pvedaemon -f")
        print("   tail -f /var/log/daemon.log")
        print()
        print("3️⃣ TESTEZ la configuration:")
        print("   perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm")
        print("   pvesm status")
        print()
        print("4️⃣ VÉRIFIEZ les permissions des fichiers:")
        print("   ls -la /usr/share/perl5/PVE/Storage/S3*")
        print("   chmod 644 /usr/share/perl5/PVE/Storage/S3Plugin.pm")
        print()
        print("5️⃣ FORCEZ le rechargement du cache Proxmox:")
        print("   systemctl reload-or-restart pvedaemon")
        print("   # Puis rafraîchissez l'interface web (F5)")
        print()
        print("⚠️  ERREURS COMMUNES:")
        print("   • Fichiers mal copiés → Relancez l'installation")
        print("   • Syntaxe Perl incorrecte → Vérifiez les logs")
        print("   • Cache web → Videz le cache navigateur (Ctrl+F5)")
        
        print("\n" + "="*60)
        print("   PROCHAINES ÉTAPES")
        print("="*60)
        print("1. Vérifiez la connectivité: pve-s3-maintenance --storage {} --action status".format(storage_name))
        print("2. Testez avec un petit fichier de sauvegarde")
        print("3. Configurez les sauvegardes automatiques dans Proxmox")
        print("4. Consultez /var/log/pve/ pour les logs en cas de problème")
        print()
        print("📞 Support: Si le problème persiste, partagez les logs de:")
        print("   • journalctl -u pvedaemon --since '1 hour ago'")
        print("   • /var/log/pve/storage-s3.log")
        
    def run(self):
        self.prompt_for_configuration()
        self.create_storage_config()
        self.display_information()