#!/usr/bin/env python3
"""
INSTRUCTIONS D'UTILISATION :

1. Copiez ce script sur votre serveur Proxmox :
   scp diagnostic-proxmox-simple.py root@<IP-PROXMOX>:/root/

2. Rendez-le exécutable :
   chmod +x /root/diagnostic-proxmox-simple.py

3. Exécutez-le :
   python3 /root/diagnostic-proxmox-simple.py
"""

import os
import subprocess

def cmd(command):
    """Exécute une commande et retourne le résultat"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout.strip()
    except:
        return False, ""

print("🔍 DIAGNOSTIC RAPIDE S3 PLUGIN")
print("=" * 50)

# 1. Fichiers
print("\n📁 FICHIERS DU PLUGIN:")
files = [
    "/usr/share/perl5/PVE/Storage/S3Plugin.pm",
    "/usr/share/perl5/PVE/Storage/S3/",
    "/usr/local/bin/pve-s3-backup"
]
files_ok = 0
for f in files:
    exists = os.path.exists(f)
    print(f"{'✅' if exists else '❌'} {f}")
    if exists: files_ok += 1

# 2. Syntaxe Perl
print("\n🔍 SYNTAXE PERL:")
if os.path.exists("/usr/share/perl5/PVE/Storage/S3Plugin.pm"):
    ok, out = cmd("perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm 2>&1")
    if "syntax OK" in out:
        print("✅ Syntaxe correcte")
    else:
        print(f"❌ Erreur: {out}")
else:
    print("❌ Fichier principal manquant")

# 3. Services
print("\n🔄 SERVICES:")
for service in ["pvedaemon", "pveproxy"]:
    ok, _ = cmd(f"systemctl is-active {service}")
    print(f"{'✅' if ok else '❌'} {service}")

# 4. Configuration
print("\n⚙️  CONFIGURATION:")
if os.path.exists("/etc/pve/storage.cfg"):
    with open("/etc/pve/storage.cfg") as f:
        content = f.read()
    if "s3:" in content:
        print("✅ Configuration S3 trouvée")
        # Afficher la config S3
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if line.startswith('s3:'):
                print(f"📋 {line}")
                j = i + 1
                while j < len(lines) and lines[j].startswith('    '):
                    print(f"   {lines[j]}")
                    j += 1
                break
    else:
        print("❌ Pas de configuration S3")
else:
    print("❌ /etc/pve/storage.cfg manquant")

# 5. Test pvesm
print("\n📦 GESTIONNAIRE STOCKAGE:")
ok, out = cmd("pvesm status")
if ok:
    print("✅ pvesm fonctionne")
    if "s3" in out.lower():
        print("✅ Stockage S3 détecté")
    else:
        print("⚠️  Pas de stockage S3 visible")
        print("💡 Stockages actuels:")
        for line in out.split('\n')[1:3]:  # Premières lignes
            if line.strip():
                print(f"   {line}")
else:
    print("❌ pvesm ne fonctionne pas")

# SOLUTIONS
print("\n🔧 SOLUTIONS:")
if files_ok < 3:
    print("📌 Fichiers manquants → Relancer l'installation")
    
ok_daemon, _ = cmd("systemctl is-active pvedaemon")
ok_proxy, _ = cmd("systemctl is-active pveproxy") 
if not ok_daemon or not ok_proxy:
    print("📌 Services inactifs → Exécuter:")
    print("   systemctl restart pvedaemon pveproxy")

print("\n📋 LOGS RÉCENTS (si erreurs):")
ok, logs = cmd("journalctl -u pvedaemon --since '10 minutes ago' | grep -i error | tail -3")
if logs:
    for line in logs.split('\n'):
        print(f"   ⚠️  {line}")
else:
    print("   ✅ Pas d'erreur récente")

print("\n✅ DIAGNOSTIC TERMINÉ")
print("📌 Si problème persiste: videz cache navigateur (Ctrl+F5)")