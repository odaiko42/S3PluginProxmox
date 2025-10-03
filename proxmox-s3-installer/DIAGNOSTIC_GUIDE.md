# 🔍 Guide de diagnostic - Plugin S3 Proxmox

## Le plugin ne s'affiche pas dans l'interface ?

### Méthode 1 : Diagnostic automatique (Recommandé)

Copiez le fichier `diagnostic-proxmox.py` sur votre serveur Proxmox et exécutez :

```bash
# Sur le serveur Proxmox (en tant que root)
python3 diagnostic-proxmox.py
```

Ce script vérifie automatiquement :
- ✅ Présence des fichiers
- ✅ Syntaxe Perl
- ✅ État des services  
- ✅ Configuration storage.cfg
- ✅ Logs d'erreur

### Méthode 2 : Diagnostic rapide manuel

Exécutez ces commandes sur votre serveur Proxmox :

```bash
# 1. Vérifier les fichiers du plugin
ls -la /usr/share/perl5/PVE/Storage/S3Plugin.pm

# 2. Tester la syntaxe Perl
perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm

# 3. Vérifier les services
systemctl status pvedaemon pveproxy

# 4. Redémarrer si nécessaire
systemctl restart pvedaemon pveproxy

# 5. Tester le gestionnaire de stockage
pvesm status
```

### Méthode 3 : Script automatique rapide

```bash
# Télécharger et exécuter le script de vérification rapide
curl -s https://raw.githubusercontent.com/votre-repo/quick-check.sh | bash
```

## ⚠️ Erreurs courantes et solutions

### Erreur 1 : "S3Plugin.pm not found"
**Cause** : Fichiers du plugin non copiés
**Solution** : 
```bash
# Relancer l'installation
python src/main.py <IP_PROXMOX> <USERNAME>
```

### Erreur 2 : "syntax error in S3Plugin.pm" 
**Cause** : Fichier corrompu lors de la copie
**Solution** :
```bash
# Vérifier l'intégrité et relancer
perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm
# Si erreur, relancer l'installation
```

### Erreur 3 : "pvedaemon failed to start"
**Cause** : Erreur dans la configuration ou le plugin
**Solution** :
```bash
# Consulter les logs détaillés
journalctl -u pvedaemon -f
# Corriger les erreurs signalées
```

### Erreur 4 : Plugin installé mais invisible dans l'interface
**Cause** : Cache du navigateur ou services non redémarrés  
**Solution** :
```bash
# 1. Redémarrer les services
systemctl restart pvedaemon pveproxy
# 2. Dans le navigateur : Ctrl+F5 (vider le cache)
# 3. Attendre 30 secondes
```

## 📊 Codes de diagnostic

Le script de diagnostic retourne ces codes :

- **✅ VERT** : Tout fonctionne correctement
- **⚠️ ORANGE** : Avertissement, peut fonctionner  
- **❌ ROUGE** : Erreur critique, ne fonctionnera pas

## 🛠️ Réparation automatique

Si des problèmes sont détectés, le script propose des corrections automatiques :

```bash
# Exemple de sortie du diagnostic
❌ pvedaemon - Inactif
🔧 SOLUTION PROPOSÉE: systemctl restart pvedaemon

❌ S3Plugin.pm - Syntaxe incorrecte  
🔧 SOLUTION PROPOSÉE: Relancer l'installation du plugin
```

## 📞 Support avancé

Si le diagnostic automatique ne résout pas le problème :

1. **Collectez les logs** :
```bash
# Logs système
journalctl -u pvedaemon --since "1 hour ago" > pvedaemon.log

# Configuration actuelle  
cat /etc/pve/storage.cfg > storage.cfg

# Informations système
uname -a > system-info.txt
cat /etc/pve/version >> system-info.txt
```

2. **Partagez ces fichiers** avec les détails de votre configuration S3

## 🔄 Réinstallation complète

Si rien ne fonctionne, procédure de réinstallation complète :

```bash
# 1. Nettoyer les anciens fichiers
rm -rf /usr/share/perl5/PVE/Storage/S3*
rm -f /usr/local/bin/pve-s3-*

# 2. Sauvegarder la config actuelle
cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup

# 3. Supprimer les entrées S3 de la config
sed -i '/^s3:/,/^$/d' /etc/pve/storage.cfg

# 4. Redémarrer les services
systemctl restart pvedaemon pveproxy

# 5. Relancer l'installation complète
python src/main.py <IP_PROXMOX> <USERNAME>
```

## ✅ Test de fonctionnement final

Une fois le plugin visible dans l'interface :

```bash
# 1. Tester la connectivité S3
pve-s3-maintenance --storage <nom-stockage> --action status

# 2. Tester un petit upload
echo "test" > /tmp/test.txt
pve-s3-backup --storage <nom-stockage> --source /tmp/test.txt

# 3. Vérifier dans l'interface Proxmox
# Datacenter > Storage > Votre stockage S3 > Contenu
```

---

💡 **Conseil** : Gardez ce guide à portée de main lors de l'installation du plugin sur de nouveaux serveurs Proxmox.