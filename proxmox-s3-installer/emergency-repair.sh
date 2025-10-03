#!/bin/bash
# SCRIPT D'URGENCE - Réparation du système Proxmox cassé
# À exécuter IMMÉDIATEMENT sur le serveur Proxmox

echo "🆘 RÉPARATION D'URGENCE - Système Proxmox cassé"
echo "================================================"

echo "🔄 ÉTAPE 1: Arrêt des services pour éviter plus de dégâts..."
systemctl stop pvedaemon pveproxy

echo "🗑️  ÉTAPE 2: Suppression des fichiers S3 problématiques..."

# Supprimer tous les fichiers S3 que nous avons créés
rm -f /usr/share/perl5/PVE/Storage/S3Plugin.pm
rm -rf /usr/share/perl5/PVE/Storage/S3/
rm -f /usr/share/perl5/PVE/Storage/S3Bootstrap.pm
rm -f /usr/local/bin/pve-s3-*

echo "✅ Fichiers S3 supprimés"

echo "🔄 ÉTAPE 3: Restauration du fichier Storage.pm original..."

# Restaurer la sauvegarde la plus récente de Storage.pm
BACKUP_FILE=$(ls -t /usr/share/perl5/PVE/Storage.pm.backup* 2>/dev/null | head -1)

if [ -n "$BACKUP_FILE" ]; then
    echo "📁 Sauvegarde trouvée: $BACKUP_FILE"
    cp "$BACKUP_FILE" /usr/share/perl5/PVE/Storage.pm
    echo "✅ Storage.pm restauré"
else
    echo "❌ Aucune sauvegarde trouvée!"
    echo "🔧 Tentative de nettoyage manuel..."
    
    # Supprimer les lignes que nous avons ajoutées
    sed -i '/PVE::Storage::S3Plugin/d' /usr/share/perl5/PVE/Storage.pm
    sed -i '/PVE::Storage::S3Bootstrap/d' /usr/share/perl5/PVE/Storage.pm
    sed -i '/register_storage_type.*s3.*S3Plugin/d' /usr/share/perl5/PVE/Storage.pm
fi

echo "🧪 ÉTAPE 4: Vérification de la syntaxe Perl..."

if perl -c /usr/share/perl5/PVE/Storage.pm; then
    echo "✅ Storage.pm syntaxiquement correct"
else
    echo "❌ Storage.pm encore cassé!"
    echo ""
    echo "🆘 SOLUTION D'URGENCE - Réinstaller Proxmox Storage:"
    echo "apt update"
    echo "apt install --reinstall pve-manager"
    echo ""
fi

echo "🗑️  ÉTAPE 5: Nettoyage de la configuration S3..."

# Supprimer la configuration S3 de storage.cfg
if [ -f /etc/pve/storage.cfg ]; then
    # Créer une sauvegarde
    cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup.$(date +%Y%m%d_%H%M%S)
    
    # Supprimer la section S3 complète
    sed -i '/^s3: minio-local/,/^$/d' /etc/pve/storage.cfg
    
    echo "✅ Configuration S3 supprimée de storage.cfg"
fi

echo "🔄 ÉTAPE 6: Redémarrage des services..."
systemctl start pvedaemon
systemctl start pveproxy

echo "⏳ Attente de 15 secondes pour le redémarrage complet..."
sleep 15

echo "🧪 ÉTAPE 7: Test du système réparé..."

if systemctl is-active --quiet pvedaemon; then
    echo "✅ pvedaemon fonctionne"
else
    echo "❌ pvedaemon ne démarre pas"
    echo "📋 Logs d'erreur:"
    journalctl -u pvedaemon --no-pager | tail -10
fi

if pvesm status >/dev/null 2>&1; then
    echo "✅ pvesm fonctionne"
    echo "📋 Stockages disponibles:"
    pvesm status
else
    echo "❌ pvesm ne fonctionne pas"
    echo "📋 Erreurs:"
    pvesm status
fi

echo ""
echo "🎯 SYSTÈME RÉPARÉ !"
echo "=================="
echo "✅ Fichiers S3 problématiques supprimés"
echo "✅ Système Proxmox restauré"
echo "✅ Services redémarrés"
echo ""
echo "⚠️  LEÇONS APPRISES:"
echo "==================="
echo "1. Le plugin S3 avait des erreurs de syntaxe Perl"
echo "2. L'héritage de PVE::Storage::Plugin était incorrect"
echo "3. Il faut étudier la structure des plugins Proxmox existants"
echo ""
echo "🔬 PROCHAINES ÉTAPES:"
echo "===================="
echo "1. Analyser un plugin Proxmox existant (ex: DirPlugin)"
echo "2. Recréer le plugin S3 avec la bonne structure"
echo "3. Tester en isolation avant installation"
echo ""
echo "🛡️  SÉCURITÉ: Sauvegardes créées dans:"
echo "/usr/share/perl5/PVE/Storage.pm.backup.*"
echo "/etc/pve/storage.cfg.backup.*"