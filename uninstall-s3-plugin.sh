#!/bin/bash

# Désinstallation du plugin S3 pour Proxmox VE
# Ce script retire le plugin proprement

PLUGIN_FILE="S3Plugin.pm"
CUSTOM_PLUGIN_DIR="/usr/share/perl5/PVE/Storage/Custom"
LOADER_FILE="/usr/share/perl5/PVE/Storage/S3PluginLoader.pm"
INIT_FILE="/usr/share/perl5/PVE/Storage.pm"

echo "=== Désinstallation du plugin S3 ==="

# Supprimer le plugin
if [ -f "$CUSTOM_PLUGIN_DIR/$PLUGIN_FILE" ]; then
    rm -f "$CUSTOM_PLUGIN_DIR/$PLUGIN_FILE"
    echo "✓ Plugin S3 supprimé"
fi

# Retirer les références du fichier Storage.pm
STORAGE_FILE="/usr/share/perl5/PVE/Storage.pm"
if [ -f "$STORAGE_FILE" ]; then
    if grep -q "S3Plugin" "$STORAGE_FILE"; then
        # Faire une sauvegarde
        cp "$STORAGE_FILE" "$STORAGE_FILE.backup.uninstall.$(date +%Y%m%d_%H%M%S)"
        
        # Supprimer les lignes du plugin S3
        sed -i '/use PVE::Storage::Custom::S3Plugin;/d' "$STORAGE_FILE"
        sed -i '/PVE::Storage::Custom::S3Plugin->register();/d' "$STORAGE_FILE"
        
        echo "✓ Références S3 supprimées de Storage.pm"
    fi
fi

# Redémarrer les services
echo "Redémarrage des services Proxmox..."
systemctl restart pveproxy
systemctl restart pvedaemon

echo ""
echo "=== Désinstallation terminée ==="
echo "Le plugin S3 ne devrait plus apparaître dans l'interface"
echo ""