# Commandes de diagnostic à copier-coller sur le serveur Proxmox
# Copiez et collez ces commandes une par une dans votre terminal SSH

# === VÉRIFICATION RAPIDE PLUGIN S3 PROXMOX ===

# 1. Vérifier si les fichiers du plugin existent
echo "=== FICHIERS DU PLUGIN ==="
ls -la /usr/share/perl5/PVE/Storage/S3Plugin.pm
ls -la /usr/share/perl5/PVE/Storage/S3/
ls -la /usr/local/bin/pve-s3-*

# 2. Tester la syntaxe Perl du plugin principal  
echo -e "\n=== SYNTAXE PERL ==="
perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm

# 3. Vérifier l'état des services
echo -e "\n=== SERVICES ==="
systemctl status pvedaemon --no-pager -l
systemctl status pveproxy --no-pager -l

# 4. Vérifier la configuration S3
echo -e "\n=== CONFIGURATION S3 ==="
cat /etc/pve/storage.cfg | grep -A 15 "^s3:"

# 5. Tester le gestionnaire de stockage Proxmox
echo -e "\n=== GESTIONNAIRE STOCKAGE ==="
pvesm status

# 6. Vérifier les logs récents
echo -e "\n=== LOGS RÉCENTS ==="
journalctl -u pvedaemon --since "1 hour ago" | tail -10

# 7. Rechercher des erreurs liées à S3
echo -e "\n=== ERREURS S3 ==="
journalctl -u pvedaemon | grep -i "s3\|storage" | tail -5

# === SOLUTIONS SI PROBLÈME ===

# Si le plugin ne s'affiche pas, exécutez ces commandes :
echo -e "\n=== REDÉMARRAGE SERVICES ==="
echo "Redémarrage en cours..."
systemctl restart pvedaemon
systemctl restart pveproxy
echo "Services redémarrés. Attendez 10 secondes puis vérifiez l'interface web."

# Vérification finale
echo -e "\n=== VÉRIFICATION FINALE ==="
sleep 3
pvesm status | grep -i s3 && echo "✅ Stockage S3 détecté!" || echo "❌ Stockage S3 non visible"

echo -e "\n=== RÉSUMÉ ==="
echo "1. Si les fichiers manquent → Relancer l'installation"
echo "2. Si erreurs de syntaxe → Vérifier les logs ci-dessus"
echo "3. Si services inactifs → Commandes de redémarrage exécutées"
echo "4. Si toujours pas visible → Vider le cache navigateur (Ctrl+F5)"