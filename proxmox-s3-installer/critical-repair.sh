#!/bin/bash
# RÉPARATION CRITIQUE - Nettoyage complet du système Proxmox
# À exécuter quand les sauvegardes ne marchent pas

echo "🆘 RÉPARATION CRITIQUE - Nettoyage complet"
echo "=========================================="

echo "🛑 Arrêt de tous les services Proxmox..."
systemctl stop pvedaemon pveproxy pvestatd

echo "🔍 Diagnostic des fichiers corrompus..."

# Vérifier tous les fichiers Storage
echo "📋 État des fichiers Storage :"
ls -la /usr/share/perl5/PVE/Storage*

# Chercher toutes les références S3 dans le système
echo "🔍 Recherche des références S3 dans le système :"
find /usr/share/perl5/PVE/ -name "*.pm" -exec grep -l "S3Plugin\|S3Bootstrap" {} \; 2>/dev/null

echo "🗑️  Suppression complète de tous les restes S3..."

# Supprimer TOUTES les références S3 de tous les fichiers
find /usr/share/perl5/PVE/ -name "*.pm" -exec sed -i '/S3Plugin/d; /S3Bootstrap/d; /register.*s3/d' {} \; 2>/dev/null

# Supprimer les fichiers résiduels
rm -f /usr/share/perl5/PVE/Storage/S3*
rm -rf /usr/share/perl5/PVE/Storage/S3/
rm -f /usr/local/bin/pve-s3-*

echo "🔧 Tentative de réparation manuelle de Storage.pm..."

# Si pas de sauvegarde valide, créer une version minimale
if ! perl -c /usr/share/perl5/PVE/Storage.pm 2>/dev/null; then
    echo "❌ Storage.pm corrompu - Réinstallation nécessaire"
    
    # Forcer la réinstallation
    apt update
    apt install --reinstall --force-yes libpve-storage-perl pve-manager
    
    echo "✅ Packages réinstallés"
fi

echo "🧪 Test de la syntaxe après nettoyage..."
if perl -c /usr/share/perl5/PVE/Storage.pm; then
    echo "✅ Storage.pm réparé"
else
    echo "❌ Storage.pm toujours cassé"
    
    echo "🆘 SOLUTION ULTIME - Réinstallation complète Proxmox VE"
    echo "======================================================="
    echo "Exécutez ces commandes :"
    echo "apt update"
    echo "apt install --reinstall proxmox-ve pve-manager pve-kernel-6.8"
    echo "systemctl reboot"
    echo ""
    echo "OU restaurez depuis une sauvegarde système complète"
fi

echo "🔄 Redémarrage des services..."
systemctl start pvedaemon
sleep 5
systemctl start pveproxy
systemctl start pvestatd

echo "⏳ Attente de stabilisation (20 secondes)..."
sleep 20

echo "🧪 Test final du système..."

if systemctl is-active --quiet pvedaemon; then
    echo "✅ pvedaemon fonctionne"
else
    echo "❌ pvedaemon ne démarre pas"
    journalctl -u pvedaemon --no-pager | tail -5
fi

if pvesm status >/dev/null 2>&1; then
    echo "✅ pvesm fonctionne"
    pvesm status
    echo ""
    echo "🎉 SYSTÈME RÉPARÉ AVEC SUCCÈS !"
else
    echo "❌ pvesm ne fonctionne toujours pas"
    echo ""
    echo "🆘 DERNIÈRE OPTION - CONTACT SUPPORT PROXMOX"
    echo "============================================="
    echo "Le système nécessite une intervention manuelle experte"
    echo "ou une restauration complète depuis sauvegarde."
fi

echo ""
echo "📊 RÉSUMÉ DE L'ÉTAT SYSTÈME :"
echo "============================="
echo "Services Proxmox :"
systemctl status pvedaemon --no-pager | grep "Active:"
systemctl status pveproxy --no-pager | grep "Active:"
echo ""
echo "Stockages disponibles :"
pvesm status 2>/dev/null || echo "Aucun stockage disponible"