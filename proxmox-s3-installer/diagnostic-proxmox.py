#!/usr/bin/env python3
"""
Script de diagnostic post-installation pour le plugin S3 Proxmox
À exécuter sur le serveur Proxmox pour vérifier l'installation
"""

import subprocess
import os
import sys

def run_command(cmd, description=""):
    """Exécute une commande et retourne le résultat"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def print_section(title):
    """Affiche une section avec un titre formaté"""
    print("\n" + "="*60)
    print(f"   {title}")
    print("="*60)

def check_files():
    """Vérification des fichiers du plugin"""
    print_section("VÉRIFICATION DES FICHIERS")
    
    required_files = [
        "/usr/share/perl5/PVE/Storage/S3Plugin.pm",
        "/usr/share/perl5/PVE/Storage/S3/Client.pm",
        "/usr/share/perl5/PVE/Storage/S3/Config.pm",
        "/usr/share/perl5/PVE/Storage/S3/Auth.pm",
        "/usr/share/perl5/PVE/Storage/S3/Transfer.pm",
        "/usr/share/perl5/PVE/Storage/S3/Metadata.pm",
        "/usr/share/perl5/PVE/Storage/S3/Utils.pm",
        "/usr/share/perl5/PVE/Storage/S3/Exception.pm",
        "/usr/local/bin/pve-s3-backup",
        "/usr/local/bin/pve-s3-restore", 
        "/usr/local/bin/pve-s3-maintenance"
    ]
    
    missing_files = []
    for file_path in required_files:
        if os.path.exists(file_path):
            print(f"✅ {file_path}")
            
            # Vérifier les permissions
            stat_info = os.stat(file_path)
            perms = oct(stat_info.st_mode)[-3:]
            
            if file_path.endswith('.pm'):
                if perms != '644':
                    print(f"   ⚠️  Permissions incorrectes: {perms} (devrait être 644)")
            elif '/bin/' in file_path:
                if perms != '755':
                    print(f"   ⚠️  Permissions incorrectes: {perms} (devrait être 755)")
        else:
            print(f"❌ {file_path} - MANQUANT")
            missing_files.append(file_path)
    
    return len(missing_files) == 0

def check_perl_syntax():
    """Vérification de la syntaxe Perl"""
    print_section("VÉRIFICATION SYNTAXE PERL")
    
    perl_files = [
        "/usr/share/perl5/PVE/Storage/S3Plugin.pm",
        "/usr/share/perl5/PVE/Storage/S3/Client.pm",
        "/usr/share/perl5/PVE/Storage/S3/Config.pm",
        "/usr/share/perl5/PVE/Storage/S3/Auth.pm",
        "/usr/share/perl5/PVE/Storage/S3/Transfer.pm",
        "/usr/share/perl5/PVE/Storage/S3/Metadata.pm",
        "/usr/share/perl5/PVE/Storage/S3/Utils.pm",
        "/usr/share/perl5/PVE/Storage/S3/Exception.pm"
    ]
    
    all_syntax_ok = True
    for perl_file in perl_files:
        if os.path.exists(perl_file):
            success, stdout, stderr = run_command(f"perl -c {perl_file}")
            if success and "syntax OK" in stderr:
                print(f"✅ {os.path.basename(perl_file)} - Syntaxe OK")
            else:
                print(f"❌ {os.path.basename(perl_file)} - ERREUR SYNTAXE:")
                print(f"   {stderr}")
                all_syntax_ok = False
        else:
            print(f"⚠️  {perl_file} - Fichier manquant")
            all_syntax_ok = False
    
    return all_syntax_ok

def check_services():
    """Vérification des services Proxmox"""
    print_section("VÉRIFICATION DES SERVICES")
    
    services = ['pvedaemon', 'pveproxy', 'pvestatd']
    all_services_ok = True
    
    for service in services:
        success, stdout, stderr = run_command(f"systemctl is-active {service}")
        if success and stdout == "active":
            print(f"✅ {service} - Actif")
        else:
            print(f"❌ {service} - Inactif ou erreur")
            all_services_ok = False
    
    return all_services_ok

def check_storage_config():
    """Vérification de la configuration storage.cfg"""
    print_section("VÉRIFICATION CONFIGURATION")
    
    config_file = "/etc/pve/storage.cfg"
    
    if not os.path.exists(config_file):
        print(f"❌ {config_file} - Fichier manquant")
        return False
    
    with open(config_file, 'r') as f:
        content = f.read()
    
    if 's3:' in content:
        print("✅ Configuration S3 trouvée dans storage.cfg")
        print("\nConfiguration S3 actuelle:")
        print("-" * 40)
        
        lines = content.split('\n')
        in_s3_section = False
        for line in lines:
            if line.startswith('s3:'):
                in_s3_section = True
                print(f"📋 {line}")
            elif in_s3_section and line.startswith('    '):
                print(f"   {line}")
            elif in_s3_section and line.strip() == '':
                continue
            elif in_s3_section:
                in_s3_section = False
        
        print("-" * 40)
        return True
    else:
        print("❌ Aucune configuration S3 trouvée dans storage.cfg")
        return False

def check_pvesm_status():
    """Vérification du statut via pvesm"""
    print_section("TEST PVESM (GESTIONNAIRE DE STOCKAGE)")
    
    # Test pvesm status général
    success, stdout, stderr = run_command("pvesm status")
    if success:
        print("✅ pvesm status fonctionne")
        
        # Chercher les stockages S3
        if 's3' in stdout.lower():
            print("✅ Stockage S3 détecté dans la liste")
            print("\nStockages détectés:")
            for line in stdout.split('\n')[1:]:  # Skip header
                if line.strip():
                    print(f"   📦 {line}")
        else:
            print("⚠️  Aucun stockage S3 visible dans la liste")
            print("\nStockages actuels:")
            for line in stdout.split('\n')[1:]:  # Skip header
                if line.strip():
                    print(f"   📦 {line}")
    else:
        print(f"❌ Erreur pvesm status: {stderr}")
        return False
    
    return True

def check_logs():
    """Vérification des logs"""
    print_section("VÉRIFICATION DES LOGS")
    
    # Journalctl pour pvedaemon
    success, stdout, stderr = run_command("journalctl -u pvedaemon --since '1 hour ago' | tail -10")
    if success and stdout:
        print("📋 Derniers logs pvedaemon (1h):")
        for line in stdout.split('\n')[-5:]:  # Dernières 5 lignes
            if line.strip():
                print(f"   {line}")
    
    # Vérifier si le fichier de log S3 existe
    s3_log = "/var/log/pve/storage-s3.log"
    if os.path.exists(s3_log):
        print(f"✅ {s3_log} existe")
        with open(s3_log, 'r') as f:
            content = f.read()[-1000:]  # Derniers 1000 caractères
            if content.strip():
                print("📋 Contenu récent:")
                print(content)
            else:
                print("📋 Fichier vide")
    else:
        print(f"ℹ️  {s3_log} n'existe pas encore (normal si pas encore utilisé)")

def provide_solutions(files_ok, syntax_ok, services_ok, config_ok):
    """Propose des solutions basées sur les résultats"""
    print_section("RECOMMANDATIONS")
    
    if not files_ok:
        print("🔧 SOLUTION - Fichiers manquants:")
        print("   Relancez l'installation du plugin:")
        print("   python src/main.py <IP_PROXMOX> <USERNAME>")
    
    if not syntax_ok:
        print("🔧 SOLUTION - Erreurs de syntaxe:")
        print("   Vérifiez que les fichiers ont été copiés correctement")
        print("   Consultez les erreurs Perl ci-dessus")
    
    if not services_ok:
        print("🔧 SOLUTION - Services inactifs:")
        print("   systemctl restart pvedaemon pveproxy pvestatd")
    
    if not config_ok:
        print("🔧 SOLUTION - Configuration manquante:")
        print("   Ajoutez une configuration S3 dans /etc/pve/storage.cfg")
        print("   Ou relancez l'assistant de configuration")
    
    if files_ok and syntax_ok and services_ok and config_ok:
        print("🎉 TOUT SEMBLE CORRECT!")
        print("Si le stockage n'apparaît toujours pas dans l'interface web:")
        print("   1. Videz le cache du navigateur (Ctrl+F5)")
        print("   2. Attendez 30 secondes après le redémarrage des services")
        print("   3. Vérifiez avec: pvesm status")

def main():
    """Fonction principale de diagnostic"""
    print("🔍 DIAGNOSTIC PLUGIN S3 PROXMOX")
    print("=" * 60)
    
    # Vérification root uniquement sur Linux
    try:
        if hasattr(os, 'geteuid') and os.geteuid() != 0:
            print("❌ Ce script doit être exécuté en tant que root sur le serveur Proxmox")
            sys.exit(1)
        elif os.name == 'nt':
            print("ℹ️  Script exécuté sur Windows - pour test uniquement")
            print("📌 Pour diagnostiquer réellement, copiez ce script sur votre serveur Proxmox")
    except:
        pass
    
    # Exécuter toutes les vérifications
    files_ok = check_files()
    syntax_ok = check_perl_syntax()
    services_ok = check_services()
    config_ok = check_storage_config()
    
    check_pvesm_status()
    check_logs()
    
    # Proposer des solutions
    provide_solutions(files_ok, syntax_ok, services_ok, config_ok)
    
    # Résumé final
    print_section("RÉSUMÉ")
    checks = [
        ("Fichiers présents", files_ok),
        ("Syntaxe Perl", syntax_ok),
        ("Services actifs", services_ok),
        ("Configuration S3", config_ok)
    ]
    
    all_ok = all(check[1] for check in checks)
    
    for name, status in checks:
        icon = "✅" if status else "❌"
        print(f"{icon} {name}")
    
    if all_ok:
        print("\n🎉 Installation semble correcte!")
        print("📌 Le plugin devrait être visible dans Proxmox > Datacenter > Storage")
    else:
        print("\n⚠️  Des problèmes ont été détectés")
        print("📌 Consultez les recommandations ci-dessus")

if __name__ == "__main__":
    main()