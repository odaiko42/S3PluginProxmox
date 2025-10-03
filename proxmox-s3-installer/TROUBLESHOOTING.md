# Guide de dépannage - Plugin S3 Proxmox

## 🚨 Problème : Le stockage S3 ne s'affiche pas dans Datacenter > Storage

### Causes communes et solutions

#### 1️⃣ REDÉMARRAGE DES SERVICES (Solution la plus courante)
```bash
# Sur le serveur Proxmox
systemctl restart pvedaemon
systemctl restart pveproxy
systemctl restart pvestatd

# Puis dans le navigateur : Ctrl+F5 (vider le cache)
```

#### 2️⃣ VÉRIFICATION DES FICHIERS COPIÉS
```bash
# Vérifier que tous les fichiers existent
ls -la /usr/share/perl5/PVE/Storage/S3Plugin.pm
ls -la /usr/share/perl5/PVE/Storage/S3/
ls -la /usr/local/bin/pve-s3-*

# Vérifier les permissions
chmod 644 /usr/share/perl5/PVE/Storage/S3Plugin.pm
chmod 644 /usr/share/perl5/PVE/Storage/S3/*.pm
chmod +x /usr/local/bin/pve-s3-*
```

#### 3️⃣ TEST DE LA SYNTAXE PERL
```bash
# Tester la syntaxe du plugin principal
perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm

# Tester tous les modules S3
find /usr/share/perl5/PVE/Storage/S3/ -name "*.pm" -exec perl -c {} \;
```

#### 4️⃣ VÉRIFICATION DES LOGS
```bash
# Logs du daemon Proxmox
journalctl -u pvedaemon -f

# Logs généraux
tail -f /var/log/daemon.log

# Logs spécifiques S3 (si créés)
tail -f /var/log/pve/storage-s3.log
```

#### 5️⃣ TEST DE LA CONFIGURATION
```bash
# Lister tous les stockages
pvesm status

# Tester spécifiquement le stockage S3
pvesm status --storage nom-de-votre-stockage-s3
```

#### 6️⃣ VÉRIFICATION DU FICHIER DE CONFIGURATION
```bash
# Vérifier la syntaxe du fichier storage.cfg
cat /etc/pve/storage.cfg

# Exemple de configuration correcte :
# s3: minio-storage
#     bucket mon-bucket
#     endpoint minio.example.com:9000
#     region us-east-1
#     access_key minioadmin
#     secret_key minioadmin
#     content backup,iso,vztmpl
```

### ⚠️ Erreurs fréquentes

#### Configuration incorrecte :
❌ **Mauvais** :
```
s3: Mon-Stockage-S3
    bucket Mon-Bucket
    endpoint http://minio:9000
```

✅ **Correct** :
```  
s3: mon-stockage-s3
    bucket mon-bucket
    endpoint minio.example.com:9000
```

#### Plugin non enregistré
Si le plugin n'est toujours pas visible, le problème peut venir de l'enregistrement du plugin dans Proxmox.

**Vérification** :
```bash
# Chercher les plugins de stockage chargés
grep -r "S3Plugin" /usr/share/perl5/PVE/Storage/
```

**Solution** : S'assurer que le plugin suit la structure exacte attendue par Proxmox.

### 🔧 Script de diagnostic automatique

Créez ce script sur votre serveur Proxmox :

```bash
#!/bin/bash
echo "=== DIAGNOSTIC PLUGIN S3 PROXMOX ==="
echo

echo "1. Vérification des fichiers..."
files=(
    "/usr/share/perl5/PVE/Storage/S3Plugin.pm"
    "/usr/share/perl5/PVE/Storage/S3/Client.pm"  
    "/usr/share/perl5/PVE/Storage/S3/Config.pm"
    "/usr/share/perl5/PVE/Storage/S3/Auth.pm"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file existe"
        perl -c "$file" 2>&1 | grep -q "syntax OK" && echo "  → Syntaxe OK" || echo "  → Erreur de syntaxe!"
    else
        echo "✗ $file MANQUANT"
    fi
done

echo
echo "2. Vérification des services..."
systemctl is-active pvedaemon >/dev/null && echo "✓ pvedaemon actif" || echo "✗ pvedaemon inactif"
systemctl is-active pveproxy >/dev/null && echo "✓ pveproxy actif" || echo "✗ pveproxy inactif"

echo
echo "3. Test des stockages..."
pvesm status | grep -q s3 && echo "✓ Stockage S3 détecté" || echo "✗ Aucun stockage S3 trouvé"

echo
echo "4. Configuration storage.cfg..."
if grep -q "^s3:" /etc/pve/storage.cfg; then
    echo "✓ Configuration S3 trouvée dans storage.cfg"
    grep -A 10 "^s3:" /etc/pve/storage.cfg
else
    echo "✗ Aucune configuration S3 dans storage.cfg"
fi

echo
echo "=== FIN DIAGNOSTIC ==="
```

### 📞 Support avancé

Si le problème persiste après ces vérifications, collectez ces informations :

```bash
# Informations système
uname -a
cat /etc/pve/version

# Logs détaillés
journalctl -u pvedaemon --since "1 hour ago" > pvedaemon.log
journalctl -u pveproxy --since "1 hour ago" > pveproxy.log

# Configuration complète
cp /etc/pve/storage.cfg storage-backup.cfg

# Liste des modules Perl chargés
perl -MModule::List -e 'print join "\n", keys %{Module::List::list_modules("PVE::")}'
```

### 🎯 Solution rapide (90% des cas)

Dans la plupart des cas, cette séquence résout le problème :

```bash
# 1. Redémarrage complet des services
systemctl restart pvedaemon pveproxy pvestatd

# 2. Attendre 10 secondes
sleep 10

# 3. Vérification
pvesm status

# 4. Dans le navigateur : Ctrl+F5 pour vider le cache
```

Si cela ne fonctionne toujours pas, le problème vient probablement des fichiers copiés ou de la configuration.