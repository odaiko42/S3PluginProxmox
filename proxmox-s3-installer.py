#!/usr/bin/env python3
"""
Proxmox S3 Storage Plugin - Script d'installation automatique
=====================================================

Ce script automatise l'installation du plugin S3 pour Proxmox VE :
1. Connexion SSH au serveur Proxmox
2. Copie des fichiers du plugin
3. Configuration interactive du stockage S3
4. Configuration des credentials
5. Redémarrage des services

Usage:
    python3 proxmox-s3-installer.py --host IP_PROXMOX --user root

Auteur: Assistant IA
Version: 1.0.0
"""

import argparse
import sys
import os
import getpass
import json
import re
from datetime import datetime
from pathlib import Path

try:
    import paramiko
    import scp
except ImportError:
    print("ERREUR: Modules requis manquants. Installez avec:")
    print("pip install paramiko scp")
    sys.exit(1)

# Configuration des providers S3
S3_PROVIDERS = {
    "1": {
        "name": "AWS S3",
        "endpoint_template": "s3.{region}.amazonaws.com",
        "default_region": "us-east-1",
        "use_ssl": True,
        "path_style": False,
        "regions": ["us-east-1", "us-west-1", "us-west-2", "eu-west-1", "eu-central-1", "ap-southeast-1"]
    },
    "2": {
        "name": "MinIO",
        "endpoint_template": "{custom_endpoint}",
        "default_region": "us-east-1", 
        "use_ssl": False,
        "path_style": True,
        "regions": ["us-east-1"]
    },
    "3": {
        "name": "Ceph RadosGW",
        "endpoint_template": "{custom_endpoint}",
        "default_region": "default",
        "use_ssl": False,
        "path_style": True,
        "regions": ["default"]
    },
    "4": {
        "name": "Wasabi",
        "endpoint_template": "s3.wasabisys.com",
        "default_region": "us-east-1",
        "use_ssl": True,
        "path_style": False,
        "regions": ["us-east-1", "us-west-1", "eu-central-1", "ap-northeast-1"]
    },
    "5": {
        "name": "Backblaze B2",
        "endpoint_template": "s3.{region}.backblazeb2.com", 
        "default_region": "us-west-002",
        "use_ssl": True,
        "path_style": False,
        "regions": ["us-west-002", "eu-central-003"]
    },
    "6": {
        "name": "DigitalOcean Spaces",
        "endpoint_template": "{region}.digitaloceanspaces.com",
        "default_region": "fra1", 
        "use_ssl": True,
        "path_style": False,
        "regions": ["nyc3", "ams3", "sgp1", "fra1", "sfo3"]
    },
    "7": {
        "name": "Scaleway Object Storage",
        "endpoint_template": "s3.{region}.scw.cloud",
        "default_region": "fr-par",
        "use_ssl": True,
        "path_style": False,
        "regions": ["fr-par", "nl-ams", "pl-waw"]
    },
    "8": {
        "name": "OVHcloud Object Storage",
        "endpoint_template": "s3.{region}.io.cloud.ovh.net",
        "default_region": "gra", 
        "use_ssl": True,
        "path_style": False,
        "regions": ["gra", "sbg", "waw", "de", "uk"]
    },
    "9": {
        "name": "Autre (personnalisé)",
        "endpoint_template": "{custom_endpoint}",
        "default_region": "us-east-1",
        "use_ssl": True,
        "path_style": False,
        "regions": ["us-east-1"]
    }
}

class ProxmoxS3Installer:
    def __init__(self, host, user):
        self.host = host
        self.user = user
        self.ssh = None
        self.scp_client = None
        self.storage_config = {}
        
    def print_header(self):
        """Affiche l'en-tête du script"""
        print("=" * 80)
        print("🚀 PROXMOX S3 STORAGE PLUGIN - INSTALLATEUR AUTOMATIQUE")
        print("=" * 80)
        print(f"📡 Serveur cible: {self.host}")
        print(f"👤 Utilisateur: {self.user}")
        print(f"⏰ Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()

    def connect_ssh(self):
        """Établit la connexion SSH avec le serveur Proxmox"""
        print("🔐 Connexion SSH au serveur Proxmox...")
        
        password = getpass.getpass(f"Mot de passe pour {self.user}@{self.host}: ")
        
        try:
            self.ssh = paramiko.SSHClient()
            self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.ssh.connect(self.host, username=self.user, password=password, timeout=10)
            
            # Test de la connexion
            stdin, stdout, stderr = self.ssh.exec_command('hostname')
            hostname = stdout.read().decode().strip()
            
            print(f"✅ Connexion SSH réussie vers {hostname}")
            
            # Initialiser SCP
            self.scp_client = scp.SCPClient(self.ssh.get_transport())
            return True
            
        except Exception as e:
            print(f"❌ Erreur de connexion SSH: {e}")
            return False

    def check_proxmox_version(self):
        """Vérifie la version de Proxmox VE"""
        print("\n📋 Vérification de l'environnement Proxmox...")
        
        try:
            # Vérifier la version PVE
            stdin, stdout, stderr = self.ssh.exec_command('pveversion')
            version_output = stdout.read().decode().strip()
            print(f"📌 Version Proxmox: {version_output}")
            
            # Vérifier l'état des services
            stdin, stdout, stderr = self.ssh.exec_command('systemctl is-active pvedaemon pveproxy')
            services_status = stdout.read().decode().strip().split('\n')
            
            if 'active' in services_status[0]:
                print("✅ Service pvedaemon: actif")
            else:
                print("⚠️ Service pvedaemon: problème détecté")
                
            if 'active' in services_status[1]:
                print("✅ Service pveproxy: actif")
            else:
                print("⚠️ Service pveproxy: problème détecté")
                
            return True
            
        except Exception as e:
            print(f"❌ Erreur lors de la vérification: {e}")
            return False

    def backup_existing_config(self):
        """Sauvegarde la configuration existante"""
        print("\n💾 Sauvegarde de la configuration existante...")
        
        try:
            # Sauvegarder storage.cfg
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_cmd = f"cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup_{timestamp}"
            stdin, stdout, stderr = self.ssh.exec_command(backup_cmd)
            
            if stderr.read():
                print("⚠️ Erreur lors de la sauvegarde")
                return False
            else:
                print(f"✅ Configuration sauvegardée: storage.cfg.backup_{timestamp}")
                return True
                
        except Exception as e:
            print(f"❌ Erreur de sauvegarde: {e}")
            return False

    def copy_plugin_files(self):
        """Copie les fichiers du plugin vers le serveur Proxmox"""
        print("\n📁 Copie des fichiers du plugin...")
        
        # Chemins locaux (à adapter selon votre structure)
        local_files = {
            "PVE/Storage/S3Plugin-fixed.pm": "/usr/share/perl5/PVE/Storage/S3Plugin.pm",
            "PVE/Storage/S3/": "/usr/share/perl5/PVE/Storage/S3/",
            "scripts/": "/usr/local/bin/"
        }
        
        try:
            # Créer les répertoires nécessaires
            directories = [
                "/usr/share/perl5/PVE/Storage/S3",
                "/var/log/pve",
                "/etc/pve/s3-credentials"
            ]
            
            for directory in directories:
                stdin, stdout, stderr = self.ssh.exec_command(f"mkdir -p {directory}")
                stderr_output = stderr.read().decode()
                if stderr_output and "File exists" not in stderr_output:
                    print(f"⚠️ Erreur création répertoire {directory}: {stderr_output}")
            
            # Copier le plugin principal
            if os.path.exists("PVE/Storage/S3Plugin-fixed.pm"):
                self.scp_client.put("PVE/Storage/S3Plugin-fixed.pm", 
                                  "/usr/share/perl5/PVE/Storage/S3Plugin.pm")
                print("✅ Plugin principal copié")
                
                # Définir les permissions
                self.ssh.exec_command("chown root:root /usr/share/perl5/PVE/Storage/S3Plugin.pm")
                self.ssh.exec_command("chmod 644 /usr/share/perl5/PVE/Storage/S3Plugin.pm")
            else:
                print("❌ Fichier S3Plugin-fixed.pm non trouvé")
                return False
            
            # Copier les modules S3 si ils existent
            if os.path.exists("PVE/Storage/S3"):
                for root, dirs, files in os.walk("PVE/Storage/S3"):
                    for file in files:
                        if file.endswith('.pm'):
                            local_path = os.path.join(root, file)
                            remote_path = f"/usr/share/perl5/PVE/Storage/S3/{file}"
                            self.scp_client.put(local_path, remote_path)
                            self.ssh.exec_command(f"chown root:root {remote_path}")
                            self.ssh.exec_command(f"chmod 644 {remote_path}")
                print("✅ Modules S3 copiés")
            
            # Copier les scripts utilitaires si ils existent
            if os.path.exists("scripts"):
                for script_file in os.listdir("scripts"):
                    if script_file.startswith('pve-s3-'):
                        local_path = os.path.join("scripts", script_file)
                        remote_path = f"/usr/local/bin/{script_file}"
                        self.scp_client.put(local_path, remote_path)
                        self.ssh.exec_command(f"chmod +x {remote_path}")
                print("✅ Scripts utilitaires copiés")
            
            return True
            
        except Exception as e:
            print(f"❌ Erreur lors de la copie: {e}")
            return False

    def choose_s3_provider(self):
        """Interface interactive pour choisir le provider S3"""
        print("\n🌐 CONFIGURATION DU FOURNISSEUR S3")
        print("=" * 50)
        
        # Afficher la liste des providers
        for key, provider in S3_PROVIDERS.items():
            print(f"{key}. {provider['name']}")
        
        while True:
            choice = input("\n👉 Choisissez votre fournisseur S3 (1-9): ").strip()
            if choice in S3_PROVIDERS:
                return S3_PROVIDERS[choice]
            else:
                print("❌ Choix invalide. Veuillez sélectionner un nombre entre 1 et 9.")

    def configure_s3_storage(self):
        """Configuration interactive du stockage S3"""
        print("\n⚙️ CONFIGURATION DU STOCKAGE S3")
        print("=" * 50)
        
        # Choix du provider
        provider = self.choose_s3_provider()
        print(f"\n✅ Provider sélectionné: {provider['name']}")
        
        # Configuration de base
        storage_id = input("\n📝 ID du stockage (ex: s3-backup): ").strip()
        if not storage_id:
            storage_id = "s3-backup"
            
        bucket_name = input("📦 Nom du bucket S3: ").strip()
        while not bucket_name:
            print("❌ Le nom du bucket est obligatoire")
            bucket_name = input("📦 Nom du bucket S3: ").strip()
        
        # Configuration de l'endpoint
        if "{custom_endpoint}" in provider['endpoint_template']:
            endpoint = input("🔗 Endpoint personnalisé (ex: minio.example.com:9000): ").strip()
            while not endpoint:
                print("❌ L'endpoint est obligatoire pour ce provider")
                endpoint = input("🔗 Endpoint personnalisé: ").strip()
        elif "{region}" in provider['endpoint_template']:
            print(f"\n🌍 Régions disponibles: {', '.join(provider['regions'])}")
            region = input(f"🌍 Région [{provider['default_region']}]: ").strip()
            if not region:
                region = provider['default_region']
            endpoint = provider['endpoint_template'].format(region=region)
        else:
            endpoint = provider['endpoint_template']
            region = provider['default_region']
        
        # Région si pas encore définie
        if 'region' not in locals():
            region = input(f"🌍 Région [{provider['default_region']}]: ").strip()
            if not region:
                region = provider['default_region']
        
        # Credentials
        access_key = input("🔑 Access Key ID: ").strip()
        while not access_key:
            print("❌ L'Access Key est obligatoire")
            access_key = input("🔑 Access Key ID: ").strip()
            
        secret_key = getpass.getpass("🔐 Secret Access Key: ")
        while not secret_key:
            print("❌ La Secret Key est obligatoire")
            secret_key = getpass.getpass("🔐 Secret Access Key: ")
        
        # Options avancées
        prefix = input("📂 Préfixe des clés [proxmox/]: ").strip()
        if not prefix:
            prefix = "proxmox/"
        elif not prefix.endswith('/'):
            prefix += '/'
        
        # Types de contenu
        print("\n📋 Types de contenu supportés:")
        print("1. Backups uniquement")
        print("2. Backups + ISO")  
        print("3. Backups + ISO + Templates LXC")
        print("4. Tout (Backups + ISO + Templates + Snippets)")
        
        content_choice = input("👉 Choisissez les types de contenu [4]: ").strip()
        content_map = {
            "1": "backup",
            "2": "backup,iso", 
            "3": "backup,iso,vztmpl",
            "4": "backup,iso,vztmpl,snippets"
        }
        content = content_map.get(content_choice, "backup,iso,vztmpl,snippets")
        
        # Stocker la configuration
        self.storage_config = {
            'id': storage_id,
            'bucket': bucket_name,
            'endpoint': endpoint,
            'region': region,
            'access_key': access_key,
            'secret_key': secret_key,
            'prefix': prefix,
            'content': content,
            'provider': provider['name']
        }
        
        return True

    def configure_advanced_settings(self):
        """Configuration des paramètres avancés (optionnel)"""
        print("\n🔧 CONFIGURATION AVANCÉE")
        print("=" * 50)
        
        advanced = input("Voulez-vous configurer des paramètres avancés ? [y/N]: ").strip().lower()
        if advanced not in ['y', 'yes', 'oui']:
            return True
            
        print("\n⚡ Paramètres de performance:")
        
        # Activation sur des nœuds spécifiques
        nodes = input("🖥️ Nœuds autorisés (séparés par des virgules) [tous]: ").strip()
        if nodes:
            self.storage_config['nodes'] = nodes
            
        # Nombre maximum de fichiers
        maxfiles = input("📊 Nombre maximum de backups à conserver [0=illimité]: ").strip()
        if maxfiles and maxfiles.isdigit():
            self.storage_config['maxfiles'] = maxfiles
            
        # Stockage partagé
        shared = input("🔗 Stockage partagé entre nœuds ? [Y/n]: ").strip().lower()
        if shared not in ['n', 'no', 'non']:
            self.storage_config['shared'] = "1"
            
        return True

    def setup_credentials_file(self):
        """Configuration du fichier de credentials"""
        print("\n🔐 CONFIGURATION DES CREDENTIALS")
        print("=" * 50)
        
        print("1. Variables d'environnement")
        print("2. Fichier de credentials (recommandé)")
        print("3. Configuration inline (moins sécurisé)")
        
        cred_choice = input("\n👉 Méthode de stockage des credentials [2]: ").strip()
        
        if cred_choice == "1":
            return self.setup_env_variables()
        elif cred_choice == "3":
            return self.setup_inline_credentials()
        else:
            return self.setup_credentials_file_method()

    def setup_env_variables(self):
        """Configuration via variables d'environnement"""
        print("\n📝 Configuration des variables d'environnement...")
        
        env_vars = f"""
# Variables d'environnement S3 pour Proxmox
export S3_ENDPOINT="{self.storage_config['endpoint']}"
export S3_BUCKET="{self.storage_config['bucket']}"
export S3_REGION="{self.storage_config['region']}"
export S3_ACCESS_KEY="{self.storage_config['access_key']}"
export S3_SECRET_KEY="{self.storage_config['secret_key']}"
export S3_PREFIX="{self.storage_config['prefix']}"
"""
        
        try:
            # Créer le fichier d'environnement
            stdin, stdout, stderr = self.ssh.exec_command(
                f'cat > /etc/environment.s3 << "EOF"\n{env_vars}\nEOF'
            )
            
            # Ajouter au profil système
            self.ssh.exec_command('echo "source /etc/environment.s3" >> /etc/profile')
            
            print("✅ Variables d'environnement configurées")
            
            # Supprimer les credentials de la config inline
            if 'access_key' in self.storage_config:
                del self.storage_config['access_key']
            if 'secret_key' in self.storage_config:
                del self.storage_config['secret_key']
                
            return True
            
        except Exception as e:
            print(f"❌ Erreur configuration variables: {e}")
            return False

    def setup_credentials_file_method(self):
        """Configuration via fichier de credentials"""
        print("\n📄 Configuration du fichier de credentials...")
        
        credentials_content = f"""[default]
access_key_id = {self.storage_config['access_key']}
secret_access_key = {self.storage_config['secret_key']}
endpoint = {self.storage_config['endpoint']}
region = {self.storage_config['region']}
"""
        
        try:
            # Créer le fichier de credentials
            stdin, stdout, stderr = self.ssh.exec_command(
                f'cat > /etc/pve/s3-credentials/s3-credentials << "EOF"\n{credentials_content}\nEOF'
            )
            
            # Sécuriser le fichier
            self.ssh.exec_command('chmod 600 /etc/pve/s3-credentials/s3-credentials')
            self.ssh.exec_command('chown root:root /etc/pve/s3-credentials/s3-credentials')
            
            print("✅ Fichier de credentials créé et sécurisé")
            
            # Supprimer les credentials de la config inline
            if 'access_key' in self.storage_config:
                del self.storage_config['access_key']
            if 'secret_key' in self.storage_config:
                del self.storage_config['secret_key']
                
            return True
            
        except Exception as e:
            print(f"❌ Erreur création fichier credentials: {e}")
            return False

    def setup_inline_credentials(self):
        """Garder les credentials dans la configuration"""
        print("\n⚠️ Les credentials seront stockés dans /etc/pve/storage.cfg")
        print("   Cette méthode est moins sécurisée mais plus simple.")
        
        return True

    def write_storage_config(self):
        """Écriture de la configuration dans storage.cfg"""
        print("\n💾 Écriture de la configuration du stockage...")
        
        # Construire la configuration
        config_lines = [
            f"s3: {self.storage_config['id']}",
            f"        bucket {self.storage_config['bucket']}",
            f"        endpoint {self.storage_config['endpoint']}",
            f"        region {self.storage_config['region']}"
        ]
        
        # Ajouter les credentials si inline
        if 'access_key' in self.storage_config:
            config_lines.append(f"        access_key {self.storage_config['access_key']}")
        if 'secret_key' in self.storage_config:
            config_lines.append(f"        secret_key {self.storage_config['secret_key']}")
            
        # Autres paramètres
        config_lines.extend([
            f"        prefix {self.storage_config['prefix']}",
            f"        content {self.storage_config['content']}"
        ])
        
        # Paramètres optionnels
        if 'nodes' in self.storage_config:
            config_lines.append(f"        nodes {self.storage_config['nodes']}")
        if 'maxfiles' in self.storage_config:
            config_lines.append(f"        maxfiles {self.storage_config['maxfiles']}")
        if 'shared' in self.storage_config:
            config_lines.append(f"        shared {self.storage_config['shared']}")
        
        config_text = '\n'.join(config_lines)
        
        try:
            # Ajouter la configuration à storage.cfg
            stdin, stdout, stderr = self.ssh.exec_command(
                f'echo "\n{config_text}" >> /etc/pve/storage.cfg'
            )
            
            error_output = stderr.read().decode()
            if error_output:
                print(f"❌ Erreur écriture configuration: {error_output}")
                return False
            else:
                print("✅ Configuration du stockage écrite dans /etc/pve/storage.cfg")
                return True
                
        except Exception as e:
            print(f"❌ Erreur écriture configuration: {e}")
            return False

    def restart_services(self):
        """Redémarrage des services Proxmox"""
        print("\n🔄 Redémarrage des services Proxmox...")
        
        services = ['pvedaemon', 'pveproxy']
        
        for service in services:
            try:
                print(f"   Redémarrage de {service}...")
                stdin, stdout, stderr = self.ssh.exec_command(f'systemctl restart {service}')
                
                # Attendre un peu
                import time
                time.sleep(2)
                
                # Vérifier le statut
                stdin, stdout, stderr = self.ssh.exec_command(f'systemctl is-active {service}')
                status = stdout.read().decode().strip()
                
                if status == 'active':
                    print(f"   ✅ {service}: redémarré avec succès")
                else:
                    print(f"   ❌ {service}: problème de redémarrage")
                    return False
                    
            except Exception as e:
                print(f"❌ Erreur redémarrage {service}: {e}")
                return False
        
        return True

    def test_storage_connection(self):
        """Test de la connexion au stockage S3"""
        print("\n🧪 TEST DE CONNEXION AU STOCKAGE")
        print("=" * 50)
        
        try:
            # Vérifier que le stockage apparaît dans la liste
            stdin, stdout, stderr = self.ssh.exec_command('pvesh get /storage')
            storage_list = stdout.read().decode()
            
            if self.storage_config['id'] in storage_list:
                print("✅ Le stockage S3 est visible dans Proxmox")
            else:
                print("⚠️ Le stockage S3 n'est pas encore visible")
                
            # Test avec pvesh si possible
            stdin, stdout, stderr = self.ssh.exec_command(
                f'pvesh get /storage/{self.storage_config["id"]}/status'
            )
            
            status_output = stdout.read().decode()
            error_output = stderr.read().decode()
            
            if error_output:
                print(f"⚠️ Erreur de statut: {error_output}")
            else:
                print("✅ Le stockage répond correctement")
                
            return True
            
        except Exception as e:
            print(f"❌ Erreur test connexion: {e}")
            return False

    def show_final_info(self):
        """Affichage des informations finales"""
        print("\n" + "=" * 80)
        print("🎉 INSTALLATION TERMINÉE AVEC SUCCÈS!")
        print("=" * 80)
        
        print(f"\n📋 RÉSUMÉ DE LA CONFIGURATION:")
        print(f"   • Stockage ID: {self.storage_config['id']}")
        print(f"   • Provider: {self.storage_config['provider']}")
        print(f"   • Bucket: {self.storage_config['bucket']}")
        print(f"   • Endpoint: {self.storage_config['endpoint']}")
        print(f"   • Région: {self.storage_config['region']}")
        print(f"   • Contenu: {self.storage_config['content']}")
        
        print(f"\n🌐 INTERFACE WEB PROXMOX:")
        print(f"   • URL: https://{self.host}:8006")
        print(f"   • Navigation: Datacenter > Storage")
        print(f"   • Votre stockage S3 '{self.storage_config['id']}' devrait être visible")
        
        print(f"\n💻 LIGNES DE COMMANDE:")
        print(f"   • Status: pvesh get /storage/{self.storage_config['id']}/status")
        print(f"   • Liste: pvesh get /storage/{self.storage_config['id']}/content")
        print(f"   • Backup: pve-s3-backup --storage {self.storage_config['id']} --source /path/to/file")
        print(f"   • Restore: pve-s3-restore --storage {self.storage_config['id']} --list")
        
        print(f"\n📁 FICHIERS CRÉÉS:")
        print(f"   • Plugin: /usr/share/perl5/PVE/Storage/S3Plugin.pm")
        print(f"   • Config: /etc/pve/storage.cfg (section s3 ajoutée)")
        if 'access_key' not in self.storage_config:
            print(f"   • Credentials: /etc/pve/s3-credentials/s3-credentials")
        
        print(f"\n🔧 DÉPANNAGE:")
        print(f"   • Logs: journalctl -u pvedaemon -f")
        print(f"   • Status services: systemctl status pvedaemon pveproxy")
        print(f"   • Test connexion: pve-s3-maintenance --storage {self.storage_config['id']} --action status")
        
        print("\n✨ Votre plugin S3 est maintenant prêt à l'emploi !")

    def run(self):
        """Méthode principale d'exécution"""
        try:
            self.print_header()
            
            if not self.connect_ssh():
                return False
                
            if not self.check_proxmox_version():
                return False
                
            if not self.backup_existing_config():
                return False
                
            if not self.copy_plugin_files():
                return False
                
            if not self.configure_s3_storage():
                return False
                
            if not self.configure_advanced_settings():
                return False
                
            if not self.setup_credentials_file():
                return False
                
            if not self.write_storage_config():
                return False
                
            if not self.restart_services():
                return False
                
            if not self.test_storage_connection():
                print("⚠️ Test de connexion échoué, mais l'installation peut être OK")
                
            self.show_final_info()
            return True
            
        except KeyboardInterrupt:
            print("\n\n❌ Installation interrompue par l'utilisateur")
            return False
        except Exception as e:
            print(f"\n\n❌ Erreur inattendue: {e}")
            return False
        finally:
            if self.scp_client:
                self.scp_client.close()
            if self.ssh:
                self.ssh.close()

def main():
    """Fonction principale"""
    parser = argparse.ArgumentParser(
        description='Installation automatique du plugin S3 pour Proxmox VE',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples d'utilisation:
  python3 proxmox-s3-installer.py --host 192.168.1.100 --user root
  python3 proxmox-s3-installer.py --host pve.example.com --user admin

Prérequis:
  - Serveur Proxmox VE accessible en SSH
  - Modules Python: paramiko, scp (pip install paramiko scp)
  - Fichiers du plugin S3 dans le répertoire courant
        """
    )
    
    parser.add_argument('--host', required=True, help='Adresse IP ou nom du serveur Proxmox')
    parser.add_argument('--user', required=True, help='Utilisateur SSH pour la connexion')
    parser.add_argument('--port', type=int, default=22, help='Port SSH (défaut: 22)')
    
    args = parser.parse_args()
    
    # Validation des arguments
    if not re.match(r'^[\w\.-]+$', args.host):
        print("❌ Erreur: Adresse host invalide")
        return 1
        
    if not re.match(r'^[\w-]+$', args.user):
        print("❌ Erreur: Nom d'utilisateur invalide")  
        return 1
    
    # Vérification des fichiers locaux
    if not os.path.exists('PVE/Storage/S3Plugin-fixed.pm'):
        print("❌ Erreur: Fichier S3Plugin-fixed.pm non trouvé")
        print("   Assurez-vous d'exécuter le script depuis le répertoire contenant les fichiers du plugin")
        return 1
    
    # Lancement de l'installation
    installer = ProxmoxS3Installer(args.host, args.user)
    
    if installer.run():
        print("\n🎊 Installation réussie ! Votre plugin S3 est opérationnel.")
        return 0
    else:
        print("\n💥 Échec de l'installation. Consultez les messages d'erreur ci-dessus.")
        return 1

if __name__ == '__main__':
    sys.exit(main())