#!/bin/bash
# Script de diagnostic spécifique basé sur les logs pvedaemon
# Logs montrent que pvedaemon fonctionne normalement, donc problème = plugin non installé

echo "🔍 DIAGNOSTIC SPÉCIFIQUE - Plugin S3 Proxmox"
echo "============================================="
echo "📋 Basé sur vos logs: pvedaemon fonctionne, donc plugin probablement non installé"
echo

echo "1️⃣ VÉRIFICATION EXHAUSTIVE DES FICHIERS..."
echo "-------------------------------------------"

# Liste complète des fichiers requis
declare -a files=(
    "/usr/share/perl5/PVE/Storage/S3Plugin.pm"
    "/usr/share/perl5/PVE/Storage/S3/Client.pm"
    "/usr/share/perl5/PVE/Storage/S3/Config.pm"
    "/usr/share/perl5/PVE/Storage/S3/Auth.pm"
    "/usr/share/perl5/PVE/Storage/S3/Transfer.pm"
    "/usr/share/perl5/PVE/Storage/S3/Metadata.pm"
    "/usr/share/perl5/PVE/Storage/S3/Utils.pm"
    "/usr/share/perl5/PVE/Storage/S3/Exception.pm"
    "/usr/local/bin/pve-s3-backup"
    "/usr/local/bin/pve-s3-restore"
    "/usr/local/bin/pve-s3-maintenance"
)

missing_count=0
present_count=0

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
        # Vérifier les permissions
        perms=$(stat -c "%a" "$file" 2>/dev/null)
        if [[ "$file" == *.pm ]]; then
            if [ "$perms" != "644" ]; then
                echo "   ⚠️  Permissions: $perms (devrait être 644)"
            fi
        elif [[ "$file" == */bin/* ]]; then
            if [ "$perms" != "755" ]; then
                echo "   ⚠️  Permissions: $perms (devrait être 755)"
            fi
        fi
        ((present_count++))
    else
        echo "❌ $file - MANQUANT"
        ((missing_count++))
    fi
done

echo
echo "📊 RÉSULTAT: $present_count présents, $missing_count manquants sur ${#files[@]} fichiers"

if [ $missing_count -gt 0 ]; then
    echo "🚨 PROBLÈME IDENTIFIÉ: Plugin pas installé ou installation incomplète"
    echo
    echo "2️⃣ VÉRIFICATION DU RÉPERTOIRE S3..."
    echo "-----------------------------------"
    if [ -d "/usr/share/perl5/PVE/Storage/S3" ]; then
        echo "✅ Répertoire S3 existe"
        echo "📋 Contenu:"
        ls -la /usr/share/perl5/PVE/Storage/S3/
    else
        echo "❌ Répertoire S3 n'existe pas"
    fi
    
    echo
    echo "3️⃣ VÉRIFICATION RÉPERTOIRE SCRIPTS..."
    echo "-------------------------------------"
    echo "📋 Scripts pve-s3-* dans /usr/local/bin/:"
    ls -la /usr/local/bin/pve-s3-* 2>/dev/null || echo "❌ Aucun script pve-s3-* trouvé"
    
else
    echo "✅ Tous les fichiers sont présents!"
    echo
    echo "2️⃣ TEST DE LA SYNTAXE PERL..."
    echo "------------------------------"
    
    perl_ok=0
    for file in "${files[@]}"; do
        if [[ "$file" == *.pm ]] && [ -f "$file" ]; then
            if perl -c "$file" 2>&1 | grep -q "syntax OK"; then
                echo "✅ $(basename "$file") - Syntaxe OK"
                ((perl_ok++))
            else
                echo "❌ $(basename "$file") - ERREUR SYNTAXE:"
                perl -c "$file" 2>&1 | grep -v "syntax OK"
            fi
        fi
    done
fi

echo
echo "3️⃣ VÉRIFICATION CONFIGURATION EXISTANTE..."
echo "-------------------------------------------"
if [ -f "/etc/pve/storage.cfg" ]; then
    if grep -q "^s3:" /etc/pve/storage.cfg; then
        echo "✅ Configuration S3 trouvée dans storage.cfg"
        echo "📋 Configuration actuelle:"
        grep -A 15 "^s3:" /etc/pve/storage.cfg
    else
        echo "❌ Aucune configuration S3 dans storage.cfg"
        echo "📋 Configurations existantes:"
        grep "^[a-z].*:" /etc/pve/storage.cfg | head -5
    fi
else
    echo "❌ Fichier storage.cfg manquant"
fi

echo
echo "4️⃣ TEST GESTIONNAIRE DE STOCKAGE..."
echo "-----------------------------------"
if command -v pvesm >/dev/null; then
    echo "✅ Commande pvesm disponible"
    if pvesm status >/dev/null 2>&1; then
        echo "✅ pvesm fonctionne"
        echo "📋 Stockages actuels:"
        pvesm status
        echo
        if pvesm status | grep -q "s3"; then
            echo "✅ Stockage S3 détecté!"
        else
            echo "❌ Aucun stockage S3 visible"
        fi
    else
        echo "❌ Erreur avec pvesm status"
    fi
else
    echo "❌ Commande pvesm non trouvée"
fi

echo
echo "🔧 DIAGNOSTIC ET SOLUTIONS:"
echo "==========================="

if [ $missing_count -gt 0 ]; then
    echo "🚨 CAUSE PRINCIPALE: Plugin non installé ($missing_count fichiers manquants)"
    echo
    echo "📌 SOLUTION IMMÉDIATE:"
    echo "   1. Le plugin S3 n'a jamais été installé sur ce serveur"
    echo "   2. Ou l'installation a échoué/été interrompue"
    echo "   3. Relancer l'installation complète:"
    echo "      python src/main.py $(hostname -I | awk '{print $1}') root"
    echo
    echo "📋 ÉTAPES À SUIVRE:"
    echo "   1. Depuis votre machine Windows:"
    echo "      cd C:\\Projects\\proxmox-s3-installer\\proxmox-s3-installer"
    echo "      python src/main.py $(hostname -I | awk '{print $1}') root"
    echo "   2. Suivre l'assistant de configuration"
    echo "   3. Vérifier que tous les fichiers sont copiés"
    echo
else
    echo "✅ Fichiers présents - Problème ailleurs"
    if [ -f "/etc/pve/storage.cfg" ] && grep -q "^s3:" /etc/pve/storage.cfg; then
        echo "✅ Configuration présente"
        echo "🔧 Solutions à essayer:"
        echo "   1. Redémarrer les services:"
        echo "      systemctl restart pvedaemon pveproxy"
        echo "   2. Vider le cache navigateur (Ctrl+F5)"
        echo "   3. Attendre 30 secondes après redémarrage"
    else
        echo "❌ Configuration manquante"
        echo "🔧 Solution: Ajouter configuration S3 dans /etc/pve/storage.cfg"
        echo "   Exemple:"
        echo "   s3: mon-stockage-s3"
        echo "       bucket mon-bucket"
        echo "       endpoint s3.amazonaws.com"
        echo "       region us-east-1"
        echo "       access_key AKIA..."
        echo "       secret_key ..."
        echo "       content backup,iso"
    fi
fi

echo
echo "📞 INFORMATIONS SYSTÈME:"
echo "========================"
echo "📋 Proxmox version: $(cat /etc/pve/version 2>/dev/null || echo 'Non trouvée')"
echo "📋 Perl version: $(perl -v | grep 'This is perl' | head -1 || echo 'Non trouvé')"
echo "📋 Dernière installation détectée: $(find /usr/share/perl5/PVE/Storage/ -name "*.pm" -newer /var/log/installer/media-info 2>/dev/null | head -1 || echo 'Aucune')"

echo
echo "✅ DIAGNOSTIC TERMINÉ"
echo "📌 Prochaine action recommandée: $([ $missing_count -gt 0 ] && echo "INSTALLER LE PLUGIN" || echo "REDÉMARRER LES SERVICES")"