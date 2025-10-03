# Plugin S3 pour Proxmox VE - Version Complète

Plugin de stockage S3 avec fonctionnalités complètes pour Proxmox VE.

## Fichiers Créés

### Modules Principaux
- `PVE/Storage/Custom/S3Client.pm` - Client HTTP S3 avec authentification AWS Signature V4
- `PVE/Storage/Custom/S3PluginFull.pm` - Plugin Proxmox complet avec vraie logique S3

### Scripts de Test
- `test_s3_client.pl` - Test du client S3 (connexion, upload/download, etc.)
- `test_s3_plugin.pl` - Test du plugin Proxmox (parsing, listing, etc.)

## Fonctionnalités Implémentées

### Client S3 (`S3Client.pm`)
- ✅ Authentification AWS Signature V4
- ✅ Requêtes HTTP S3 signées
- ✅ Listing des objets avec parsing XML
- ✅ Upload/Download de fichiers
- ✅ Métadonnées des objets (HEAD)
- ✅ Suppression d'objets
- ✅ Test de connectivité

### Plugin Proxmox (`S3PluginFull.pm`)
- ✅ Héritage correct de PVE::Storage::Plugin
- ✅ Métadonnées et configuration du plugin
- ✅ Test de status/connexion S3
- ✅ Listing des volumes existants
- ✅ Parsing des noms de fichiers Proxmox
- ✅ Support des formats : backup, images, iso, vztmpl
- ✅ Gestion des chemins virtuels S3
- ✅ Upload/Download de fichiers
- ✅ Suppression de volumes

## Installation

1. **Copier les fichiers :**
```bash
sudo mkdir -p /usr/share/perl5/PVE/Storage/Custom/
sudo cp PVE/Storage/Custom/S3Client.pm /usr/share/perl5/PVE/Storage/Custom/
sudo cp PVE/Storage/Custom/S3PluginFull.pm /usr/share/perl5/PVE/Storage/Custom/S3Plugin.pm
```

2. **Installer les dépendances :**
```bash
sudo apt-get install libwww-perl libxml-libxml-perl
```

3. **Redémarrer Proxmox :**
```bash
sudo systemctl restart pvedaemon pveproxy
```

## Configuration

Ajouter dans `/etc/pve/storage.cfg` :

```
s3: mon-s3
        bucket mon-bucket
        endpoint s3.amazonaws.com
        region us-east-1  
        access_key AKIA...
        secret_key wJal...
        prefix proxmox/
        content backup,images,iso,vztmpl
```

## Tests

### Test Client S3
```bash
cd /path/to/plugin
perl test_s3_client.pl
```

### Test Plugin Complet  
```bash
perl test_s3_plugin.pl
```

## Structure des Objets

- **Backups** : `backup-{vmid}-{date}.{ext}`
- **Images VM** : `vm-{vmid}-disk-{n}.{ext}`
- **Templates CT** : `ct-{vmid}-{name}.{ext}` 
- **ISO** : `{filename}.iso`

## Formats Supportés

- **Backups** : vma, tar, tgz
- **Images** : raw, qcow2, vmdk
- **Templates** : tar.gz, tar.xz
- **ISO** : iso

## Améliorations vs Version de Base

1. **Client S3 Complet** - Vrai client HTTP avec signature AWS
2. **Gestion des Erreurs** - Traitement des erreurs S3 et réseau
3. **Parsing XML** - Traitement correct des réponses S3
4. **Support Multi-Format** - Support de tous les formats Proxmox
5. **Métadonnées** - Gestion des tailles et dates de modification
6. **Tests Complets** - Scripts de validation fonctionnelle

## Limitations

- Pas de montage direct (téléchargement nécessaire)
- Pas de snapshots S3 natifs  
- Performance dépendante de la latence réseau
- Nécessite permissions S3 appropriées

## Permissions S3 Minimales

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": "arn:aws:s3:::mon-bucket"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
            "Resource": "arn:aws:s3:::mon-bucket/*"
        }
    ]
}
```

La taille de chaque fichier respecte la limite de 600 lignes demandée :
- S3Client.pm : ~270 lignes
- S3PluginFull.pm : ~380 lignes