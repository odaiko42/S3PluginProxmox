#!/bin/bash
# Script de diagnostic rapide à exécuter sur le serveur Proxmox
# Usage: curl -s https://example.com/quick-check.sh | bash
# Ou copier/coller les commandes ci-dessous

echo "🔍 DIAGNOSTIC RAPIDE PLUGIN S3 PROXMOX"
echo "======================================"

echo
echo "1️⃣ Vérification des fichiers principaux..."
if [ -f "/usr/share/perl5/PVE/Storage/S3Plugin.pm" ]; then
    echo "✅ S3Plugin.pm trouvé"
    perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm 2>&1 | grep -q "syntax OK" && echo "✅ Syntaxe OK" || echo "❌ Erreur de syntaxe"
else
    echo "❌ S3Plugin.pm MANQUANT - Plugin pas installé"
fi

echo
echo "2️⃣ État des services..."
for service in pvedaemon pveproxy; do
    if systemctl is-active --quiet $service; then
        echo "✅ $service actif"
    else
        echo "❌ $service inactif"
    fi
done

echo
echo "3️⃣ Configuration storage.cfg..."
if grep -q "^s3:" /etc/pve/storage.cfg 2>/dev/null; then
    echo "✅ Configuration S3 trouvée:"
    grep -A 10 "^s3:" /etc/pve/storage.cfg | head -15
else
    echo "❌ Aucune configuration S3 dans /etc/pve/storage.cfg"
fi

echo
echo "4️⃣ Test du gestionnaire de stockage..."
if pvesm status &>/dev/null; then
    echo "✅ pvesm fonctionne"
    echo "📋 Stockages détectés:"
    pvesm status | grep -E "(Name|s3)" || echo "   Aucun stockage S3 visible"
else
    echo "❌ Erreur avec pvesm"
fi

echo
echo "5️⃣ Logs récents..."
echo "📋 Dernières erreurs pvedaemon:"
journalctl -u pvedaemon --since "10 minutes ago" | grep -i error | tail -3 || echo "   Aucune erreur récente"

echo
echo "🔧 SOLUTIONS RAPIDES:"
echo "Si le plugin ne s'affiche pas:"
echo "   systemctl restart pvedaemon pveproxy"
echo "   # Puis Ctrl+F5 dans le navigateur"
echo
echo "Si des fichiers manquent:"
echo "   Relancer l'installation du plugin"
echo
echo "⚡ DIAGNOSTIC COMPLET DÉTAILLÉ:"
echo "   Copiez et exécutez diagnostic-specific.sh pour analyse complète"
echo
echo "📋 VÉRIFICATION MANUELLE RAPIDE:"
echo "   ls -la /usr/share/perl5/PVE/Storage/S3Plugin.pm"
echo "   grep 's3:' /etc/pve/storage.cfg"