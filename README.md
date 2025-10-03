# Proxmox S3 Storage Plugin

Plugin de stockage S3 pour Proxmox VE permettant l'utilisation de services de stockage objet compatibles S3 (AWS S3, MinIO, Ceph RadosGW, etc.) comme backend de stockage pour les backups, ISO et templates.

## Fonctionnalités

- **Stockage multi-format** : Support des backups (VMA, tar), images ISO, templates LXC et snippets
- **Optimisations de performance** : Upload/download multipart avec parallélisation
- **Authentification AWS Signature V4** : Compatible avec AWS S3 et services compatibles
- **Métadonnées Proxmox** : Gestion automatique des métadonnées VM/CT
- **Gestion du cycle de vie** : Transition automatique vers classes de stockage économiques
- **Chiffrement** : Support du chiffrement côté serveur (AES256, AWS KMS)
- **Outils de maintenance** : Scripts pour le nettoyage, vérification d'intégrité et maintenance

## Architecture

```
/usr/share/perl5/PVE/Storage/
├── S3Plugin.pm              # Plugin principal Proxmox
├── S3/
│   ├── Client.pm            # Client S3 bas niveau
│   ├── Config.pm            # Gestionnaire de configuration
│   ├── Auth.pm              # Authentification AWS Signature V4
│   ├── Transfer.pm          # Moteur de transfert optimisé
│   ├── Metadata.pm          # Gestion des métadonnées Proxmox
│   ├── Utils.pm             # Utilitaires communs
│   └── Exception.pm         # Gestion des exceptions
```

## Installation

### 1. Copie des fichiers

```bash
# Copie du plugin principal
sudo cp PVE/Storage/S3Plugin.pm /usr/share/perl5/PVE/Storage/

# Copie des modules S3
sudo cp -r PVE/Storage/S3/ /usr/share/perl5/PVE/Storage/

# Copie des scripts utilitaires
sudo cp scripts/* /usr/local/bin/
sudo chmod +x /usr/local/bin/pve-s3-*

# Création des répertoires de log
sudo mkdir -p /var/log/pve/
```

### 2. Configuration dans Proxmox

Ajout dans `/etc/pve/storage.cfg` :

```
s3: mon-stockage-s3
    bucket mon-bucket-proxmox
    endpoint s3.amazonaws.com
    region us-east-1
    access_key AKIA...
    secret_key ...
    prefix proxmox/
    content backup,iso,vztmpl,snippets
    storage_class STANDARD
    multipart_chunk_size 100
    max_concurrent_uploads 3
```

### 3. Configuration des credentials

**Option 1: Variables d'environnement**
```bash
export S3_ENDPOINT="s3.amazonaws.com"
export S3_BUCKET="mon-bucket-proxmox"  
export S3_REGION="us-east-1"
export S3_ACCESS_KEY="AKIA..."
export S3_SECRET_KEY="..."
export S3_PREFIX="proxmox/"
```

**Option 2: Fichier de configuration** (recommandé en production)
```bash
sudo mkdir -p /etc/pve/s3-credentials/
sudo cat > /etc/pve/s3-credentials/aws-credentials << EOF
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
endpoint = s3.amazonaws.com
region = us-east-1
EOF
sudo chmod 600 /etc/pve/s3-credentials/aws-credentials
```

## Utilisation

### Interface Web Proxmox

Une fois configuré, le stockage S3 apparaît dans l'interface Proxmox sous "Datacenter > Storage" et peut être utilisé pour :

- Stockage des backups automatiques
- Upload d'images ISO
- Stockage des templates LXC
- Sauvegarde des snippets de configuration

### Ligne de commande

**Backup manuel :**
```bash
pve-s3-backup --storage mon-stockage-s3 --source /var/lib/vz/dump/vzdump-qemu-100-*.vma.gz --vmid 100
```

**Liste des backups :**
```bash
pve-s3-restore --storage mon-stockage-s3 --list
pve-s3-restore --storage mon-stockage-s3 --list --vmid 100
```

**Restauration :**
```bash
pve-s3-restore --storage mon-stockage-s3 --source vzdump-qemu-100-2023_12_25-14_30_00.vma.gz --destination /tmp/backup-restaure.vma.gz
```

**Maintenance :**
```bash
# Statut du stockage
pve-s3-maintenance --storage mon-stockage-s3 --action status

# Nettoyage des backups anciens (> 90 jours)
pve-s3-maintenance --storage mon-stockage-s3 --action cleanup --older-than 90d

# Vérification d'intégrité
pve-s3-maintenance --storage mon-stockage-s3 --action check-integrity
```

## Configuration avancée

### Paramètres de performance

```
# Taille des chunks pour multipart upload (5-5120 MB)
multipart_chunk_size 100

# Nombre d'uploads simultanés (1-20)
max_concurrent_uploads 3

# Timeout de connexion (10-300 secondes)  
connection_timeout 60
```

### Chiffrement

```
# Chiffrement AES256
server_side_encryption AES256

# Ou chiffrement KMS
server_side_encryption aws:kms
kms_key_id arn:aws:kms:us-east-1:123456789012:key/...
```

### Cycle de vie automatique

```
# Activation de la gestion du cycle de vie
lifecycle_enabled 1

# Transition vers IA après 30 jours
transition_days 30

# Transition vers Glacier après 365 jours  
glacier_days 365
```

## Services S3 compatibles

### AWS S3
```
endpoint s3.amazonaws.com
region us-east-1
```

### MinIO
```
endpoint minio.example.com:9000
region us-east-1
```

### Ceph RadosGW
```
endpoint ceph-rgw.example.com:7480
region default
```

### Wasabi
```
endpoint s3.wasabisys.com
region us-east-1
```

## Dépannage

### Logs
```bash
# Logs généraux du plugin
tail -f /var/log/pve/storage-s3.log

# Logs système Proxmox
journalctl -u pvedaemon -f
```

### Debug
```bash
# Activation du mode debug
export PVE_S3_DEBUG=1
export PVE_S3_LOG_LEVEL=DEBUG
```

### Tests de connectivité
```bash
# Test basique
pve-s3-maintenance --storage mon-stockage-s3 --action status

# Test avec un petit fichier
echo "test" > /tmp/test.txt
pve-s3-backup --storage mon-stockage-s3 --source /tmp/test.txt --notes "test de connectivité"
```

### Problèmes courants

**Erreur d'authentification :**
- Vérifier les clés d'accès S3
- Vérifier les permissions du bucket
- Vérifier la région spécifiée

**Erreur de réseau :**
- Vérifier la connectivité réseau vers l'endpoint S3
- Vérifier les paramètres de proxy si applicable
- Augmenter le timeout de connexion

**Erreur de permissions :**
- Le compte S3 doit avoir les permissions : `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`
- Pour la gestion du cycle de vie : `s3:PutBucketLifecycle`, `s3:GetBucketLifecycle`

## Limitations

- Taille maximale de fichier : 5TB (limite S3)
- Nombre maximum de parts multipart : 10,000
- Les snapshots ne sont pas supportés nativement
- Pas de support des liens durs

## Support et développement

- **Version** : 1.0.0
- **Compatibilité** : Proxmox VE 7.0+, Perl 5.20+
- **Licence** : AGPL-3.0

### Contributions

Les contributions sont les bienvenues ! Merci de :
1. Créer une issue pour les bugs ou nouvelles fonctionnalités
2. Suivre le style de code Perl existant
3. Ajouter des tests pour les nouvelles fonctionnalités
4. Mettre à jour la documentation

### Architecture technique

Le plugin respecte l'architecture modulaire de Proxmox :
- **S3Plugin.pm** : Interface avec le système de stockage Proxmox
- **S3/Client.pm** : Communication HTTP avec l'API S3
- **S3/Auth.pm** : Implémentation AWS Signature Version 4
- **S3/Transfer.pm** : Optimisations multipart et parallélisation
- **S3/Metadata.pm** : Gestion des métadonnées spécifiques Proxmox
- **S3/Config.pm** : Validation et gestion de la configuration
- **S3/Utils.pm** : Fonctions utilitaires partagées
- **S3/Exception.pm** : Gestion centralisée des erreurs