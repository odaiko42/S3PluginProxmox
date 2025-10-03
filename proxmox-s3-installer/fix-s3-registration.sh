#!/bin/bash
# Script de correction pour enregistrer le plugin S3 dans Proxmox
# À exécuter sur le serveur Proxmox après l'installation de base

echo "🔧 CORRECTION - Enregistrement du plugin S3"
echo "============================================="

# 1. Vérifier si les fichiers du plugin existent
if [ ! -f "/usr/share/perl5/PVE/Storage/S3Plugin.pm" ]; then
    echo "❌ Plugin S3 non trouvé. Exécutez d'abord install-manual.sh"
    exit 1
fi

echo "✅ Plugin S3 trouvé"

# 2. Analyser le fichier PVE::Storage
echo "🔍 Analyse du système de storage Proxmox..."

# Chercher où sont enregistrés les autres plugins
STORAGE_FILE="/usr/share/perl5/PVE/Storage.pm"

if [ ! -f "$STORAGE_FILE" ]; then
    echo "❌ Fichier PVE::Storage.pm non trouvé"
    exit 1
fi

echo "📋 Plugins actuellement enregistrés :"
grep -n "Plugin.*register\|use.*Plugin" $STORAGE_FILE | head -10

# 3. Sauvegarde du fichier Storage.pm
echo "💾 Sauvegarde de Storage.pm..."
cp $STORAGE_FILE ${STORAGE_FILE}.backup.$(date +%Y%m%d_%H%M%S)

# 4. Ajouter l'import du plugin S3
echo "📝 Ajout de l'import S3Plugin..."

if ! grep -q "PVE::Storage::S3Plugin" $STORAGE_FILE; then
    # Trouver la ligne après les autres imports de plugins et ajouter le nôtre
    sed -i '/^use PVE::Storage:.*Plugin;/a use PVE::Storage::S3Plugin;' $STORAGE_FILE
    echo "✅ Import S3Plugin ajouté"
else
    echo "✅ Import S3Plugin déjà présent"
fi

# 5. Rechercher le pattern d'enregistrement des plugins
echo "🔍 Recherche du système d'enregistrement des plugins..."

# Dans PVE, les plugins sont généralement enregistrés dans une fonction register_all ou similaire
# Cherchons les patterns d'enregistrement
echo "📋 Patterns d'enregistrement trouvés :"
grep -n -A2 -B2 "register.*Plugin\|Plugin.*register" $STORAGE_FILE

# 6. Méthode alternative : Créer un module de bootstrap
echo "🔄 Création d'un module de bootstrap S3..."

cat > /usr/share/perl5/PVE/Storage/S3Bootstrap.pm << 'EOF'
package PVE::Storage::S3Bootstrap;

use strict;
use warnings;

use PVE::Storage::S3Plugin;

# Enregistrer automatiquement le plugin S3 au chargement du module
BEGIN {
    # Enregistrer le plugin S3 dans le système PVE
    eval {
        require PVE::Storage::Plugin;
        PVE::Storage::Plugin::register_storage_type('s3', 'PVE::Storage::S3Plugin');
    };
    
    if ($@) {
        warn "Impossible d'enregistrer le plugin S3: $@";
    }
}

1;
EOF

# 7. Charger automatiquement le bootstrap
echo "🚀 Configuration du chargement automatique..."

# Ajouter le bootstrap dans Storage.pm
if ! grep -q "S3Bootstrap" $STORAGE_FILE; then
    sed -i '/^use PVE::Storage::S3Plugin;/a use PVE::Storage::S3Bootstrap;' $STORAGE_FILE
    echo "✅ Bootstrap S3 ajouté"
fi

# 8. Méthode directe : Modifier manuellement le registre des plugins
echo "⚙️  Modification directe du registre..."

# Chercher la fonction où les plugins sont enregistrés et ajouter le nôtre
# Ceci nécessite d'analyser la structure exacte de PVE::Storage

if grep -q "register_storage_type.*dir.*DirPlugin" $STORAGE_FILE; then
    echo "✅ Système d'enregistrement trouvé"
    
    # Ajouter notre plugin après les autres
    if ! grep -q "register_storage_type.*s3.*S3Plugin" $STORAGE_FILE; then
        sed -i '/register_storage_type.*dir.*DirPlugin/a \    register_storage_type("s3", "PVE::Storage::S3Plugin");' $STORAGE_FILE
        echo "✅ Plugin S3 enregistré dans le système"
    else
        echo "✅ Plugin S3 déjà enregistré"
    fi
fi

# 9. Vérification de la syntaxe Perl
echo "🧪 Vérification de la syntaxe..."

if perl -c $STORAGE_FILE 2>/dev/null; then
    echo "✅ Syntaxe Storage.pm correcte"
else
    echo "❌ Erreur de syntaxe dans Storage.pm"
    echo "🔄 Restauration de la sauvegarde..."
    cp ${STORAGE_FILE}.backup.* $STORAGE_FILE
    echo "⚠️  Sauvegarde restaurée. Vérifiez manuellement."
fi

# 10. Test du plugin S3
echo "🧪 Test de chargement du plugin S3..."

if perl -e "use PVE::Storage::S3Plugin; print 'Plugin S3 chargé avec succès\n';" 2>/dev/null; then
    echo "✅ Plugin S3 se charge correctement"
else
    echo "❌ Erreur de chargement du plugin S3"
fi

# 11. Redémarrer les services
echo "🔄 Redémarrage des services Proxmox..."
systemctl restart pvedaemon
systemctl restart pveproxy

echo ""
echo "⏳ Attente de 10 secondes pour le redémarrage..."
sleep 10

# 12. Test final
echo "🧪 Test final du support S3..."

if pvesm status 2>&1 | grep -q "unsupported type 's3'"; then
    echo "❌ Le type S3 n'est toujours pas supporté"
    echo ""
    echo "🔧 SOLUTIONS MANUELLES À ESSAYER :"
    echo "=================================="
    echo "1. Vérifier les logs d'erreur :"
    echo "   journalctl -u pvedaemon | tail -20"
    echo ""
    echo "2. Forcer le rechargement des modules :"
    echo "   systemctl stop pvedaemon"
    echo "   systemctl start pvedaemon"
    echo ""
    echo "3. Vérifier la structure PVE::Storage :"
    echo "   perl -MPVE::Storage -e 'print join(\"\n\", keys %PVE::Storage::Plugin::storename_hash)'"
    echo ""
    echo "4. Debug du chargement des modules :"
    echo "   perl -d -MPVE::Storage::S3Plugin -e 1"
    
else
    echo "✅ Plugin S3 enregistré avec succès!"
    echo ""
    echo "🎉 SUCCÈS! Vous pouvez maintenant utiliser le stockage S3 dans Proxmox"
    echo "➡️  Allez dans : Interface Proxmox > Datacenter > Storage"
fi

echo ""
echo "📋 ÉTAT FINAL :"
echo "==============="
echo "Fichiers de sauvegarde créés dans :"
ls -la ${STORAGE_FILE}.backup.*
echo ""
echo "Configuration S3 dans :"
echo "/etc/pve/storage.cfg"
echo ""
echo "✅ Script de correction terminé"