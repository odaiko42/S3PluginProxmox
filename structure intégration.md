# Plugin S3 pour Proxmox - Structure et Intégration Complète

## Table des Matières
1. [Architecture du Plugin S3](#architecture-du-plugin-s3)
2. [Structure des Fichiers](#structure-des-fichiers)
3. [Code Source Détaillé](#code-source-détaillé)
4. [Intégration dans Proxmox](#intégration-dans-proxmox)
5. [Configuration et Déploiement](#configuration-et-déploiement)
6. [API et Interfaces](#api-et-interfaces)
7. [Gestion des Erreurs](#gestion-des-erreurs)
8. [Tests et Validation](#tests-et-validation)
9. [Optimisations et Performance](#optimisations-et-performance)
10. [Exemples d'Utilisation](#exemples-dutilisation)

## Architecture du Plugin S3

### 1. Vue d'Ensemble

```mermaid
graph TB
    A[Proxmox VE Core] --> B[Storage Manager]
    B --> C[Plugin S3]
    C --> D[AWS SDK Perl]
    C --> E[Configuration Manager]
    C --> F[Authentication Handler]
    C --> G[Transfer Manager]
    
    D --> H[AWS S3 API]
    E --> I[/etc/pve/storage.cfg]
    F --> J[AWS Credentials]
    G --> K[Multipart Upload]
    G --> L[Progress Tracking]
    
    H --> M[Amazon S3]
    H --> N[Compatible S3 Storage]
    N --> N1[MinIO]
    N --> N2[Ceph RadosGW]
    N --> N3[OpenStack Swift]
```

### 2. Composants Principaux

| Composant | Responsabilité | Fichier |
|-----------|---------------|---------|
| **Plugin Core** | Interface principale avec Proxmox | `S3Plugin.pm` |
| **S3 Client** | Communication avec API S3 | `S3Client.pm` |
| **Config Handler** | Gestion configuration | `S3Config.pm` |
| **Auth Manager** | Authentification AWS | `S3Auth.pm` |
| **Transfer Engine** | Upload/Download optimisé | `S3Transfer.pm` |
| **Metadata Handler** | Gestion métadonnées | `S3Metadata.pm` |

## Structure des Fichiers

### 1. Arborescence Complète

```
/usr/share/perl5/PVE/Storage/
├── S3Plugin.pm                 # Plugin principal
├── S3/
│   ├── Client.pm              # Client S3 bas niveau
│   ├── Config.pm              # Configuration
│   ├── Auth.pm                # Authentification
│   ├── Transfer.pm            # Gestion transferts
│   ├── Metadata.pm            # Métadonnées
│   ├── Utils.pm               # Utilitaires
│   └── Exception.pm           # Gestion erreurs
├── Custom/
│   └── S3Plugin.pm            # Plugin personnalisé
/etc/pve/
├── storage.cfg                # Configuration storage
└── s3-credentials/            # Credentials S3
    ├── aws-credentials
    └── s3-config.json
/usr/local/bin/
├── pve-s3-backup             # Script backup S3
├── pve-s3-restore            # Script restore S3
└── pve-s3-maintenance        # Maintenance S3
/var/log/pve/
└── storage-s3.log            # Logs spécifiques S3
```

### 2. Structure du Plugin Principal

```perl
# Structure générale du fichier S3Plugin.pm
package PVE::Storage::S3Plugin;

# Imports et dépendances
use strict;
use warnings;
use base qw(PVE::Storage::Plugin);

# Configuration du plugin
use constant PLUGIN_TYPE => 's3';
use constant PLUGIN_VERSION => '1.0.0';

# Méthodes principales
sub type { return PLUGIN_TYPE; }
sub plugindata { ... }
sub properties { ... }
sub options { ... }

# Opérations de base
sub path { ... }
sub create_base { ... }
sub clone_image { ... }
sub alloc_image { ... }
sub free_image { ... }

# Opérations avancées  
sub list_images { ... }
sub status { ... }
sub activate_storage { ... }
sub deactivate_storage { ... }

# Backup/Restore
sub archive_info { ... }
sub extract_vzdump_config { ... }
```

## Code Source Détaillé

### 1. Plugin Principal (S3Plugin.pm)

```perl
package PVE::Storage::S3Plugin;

use strict;
use warnings;
use base qw(PVE::Storage::Plugin);

use PVE::Tools qw(run_command file_read_firstline trim dir_glob_regex dir_glob_foreach);
use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use PVE::Cluster qw(cfs_register_file);
use PVE::Storage::S3::Client;
use PVE::Storage::S3::Config;
use PVE::Storage::S3::Auth;
use PVE::Storage::S3::Transfer;
use PVE::Storage::S3::Metadata;
use PVE::Storage::S3::Utils;

use JSON;
use File::Path qw(make_path);
use File::Basename qw(basename dirname);
use POSIX qw(strftime);

# Configuration du plugin
sub type {
    return 's3';
}

sub plugindata {
    return {
        content => [
            {
                backup => 1,
                query => 1,
            },
            {
                iso => 1,
                query => 1,
            },
            {
                vztmpl => 1,
                query => 1,  
            },
            {
                snippets => 1,
                query => 1,
            }
        ],
        format => [
            {
                raw => 1,
                qcow2 => 1,
                vmdk => 1,
                subvol => 1,
            }
        ],
    };
}

# Propriétés de configuration
sub properties {
    return {
        # Configuration S3 de base
        endpoint => {
            description => "S3 endpoint URL",
            type => 'string',
            format => 'pve-storage-server',
        },
        region => {
            description => "AWS region",
            type => 'string',
            default => 'us-east-1',
        },
        bucket => {
            description => "S3 bucket name", 
            type => 'string',
            format => 'pve-storage-id',
        },
        
        # Authentification
        access_key => {
            description => "S3 access key ID",
            type => 'string',
        },
        secret_key => {
            description => "S3 secret access key", 
            type => 'string',
        },
        session_token => {
            description => "S3 session token (for temporary credentials)",
            type => 'string',
            optional => 1,
        },
        
        # Configuration avancée
        prefix => {
            description => "Object key prefix",
            type => 'string',
            optional => 1,
            default => 'proxmox/',
        },
        storage_class => {
            description => "S3 storage class",
            type => 'string',
            enum => ['STANDARD', 'STANDARD_IA', 'ONEZONE_IA', 'REDUCED_REDUNDANCY', 
                    'GLACIER', 'DEEP_ARCHIVE', 'INTELLIGENT_TIERING'],
            default => 'STANDARD',
            optional => 1,
        },
        server_side_encryption => {
            description => "Server-side encryption",
            type => 'string', 
            enum => ['AES256', 'aws:kms'],
            optional => 1,
        },
        kms_key_id => {
            description => "KMS key ID for encryption",
            type => 'string',
            optional => 1,
        },
        
        # Performance et fiabilité
        multipart_chunk_size => {
            description => "Multipart upload chunk size (MB)",
            type => 'integer',
            minimum => 5,
            maximum => 5120,
            default => 100,
            optional => 1,
        },
        max_concurrent_uploads => {
            description => "Maximum concurrent uploads",
            type => 'integer',
            minimum => 1,
            maximum => 20,
            default => 3,
            optional => 1,
        },
        connection_timeout => {
            description => "Connection timeout (seconds)",
            type => 'integer',
            minimum => 10,
            maximum => 300,
            default => 60,
            optional => 1,
        },
        
        # Cycle de vie des objets
        lifecycle_enabled => {
            description => "Enable lifecycle management",
            type => 'boolean',
            default => 0,
            optional => 1,
        },
        transition_days => {
            description => "Days before transitioning to IA",
            type => 'integer',
            minimum => 1,
            default => 30,
            optional => 1,
        },
        glacier_days => {
            description => "Days before transitioning to Glacier",
            type => 'integer',
            minimum => 1,
            default => 365,
            optional => 1,
        },
    };
}

# Options du plugin
sub options {
    return {
        # Options obligatoires
        endpoint => { fixed => 1 },
        bucket => { fixed => 1 },
        access_key => { fixed => 1 },
        secret_key => { fixed => 1 },
        
        # Options optionnelles
        region => { optional => 1 },
        prefix => { optional => 1 },
        storage_class => { optional => 1 },
        server_side_encryption => { optional => 1 },
        kms_key_id => { optional => 1 },
        session_token => { optional => 1 },
        
        # Options de performance
        multipart_chunk_size => { optional => 1 },
        max_concurrent_uploads => { optional => 1 },
        connection_timeout => { optional => 1 },
        
        # Options de cycle de vie
        lifecycle_enabled => { optional => 1 },
        transition_days => { optional => 1 },
        glacier_days => { optional => 1 },
        
        # Options standard Proxmox
        content => { optional => 1 },
        nodes => { optional => 1 },
        disable => { optional => 1 },
        maxfiles => { optional => 1 },
        shared => { optional => 1, fixed => 1 },
    };
}

# Création du client S3
sub get_s3_client {
    my ($class, $scfg) = @_;
    
    my $config = PVE::Storage::S3::Config->new({
        endpoint => $scfg->{endpoint},
        region => $scfg->{region} // 'us-east-1',
        bucket => $scfg->{bucket},
        prefix => $scfg->{prefix} // 'proxmox/',
        storage_class => $scfg->{storage_class} // 'STANDARD',
        server_side_encryption => $scfg->{server_side_encryption},
        kms_key_id => $scfg->{kms_key_id},
        multipart_chunk_size => ($scfg->{multipart_chunk_size} // 100) * 1024 * 1024,
        max_concurrent_uploads => $scfg->{max_concurrent_uploads} // 3,
        connection_timeout => $scfg->{connection_timeout} // 60,
    });
    
    my $auth = PVE::Storage::S3::Auth->new({
        access_key => $scfg->{access_key},
        secret_key => $scfg->{secret_key},
        session_token => $scfg->{session_token},
    });
    
    return PVE::Storage::S3::Client->new($config, $auth);
}

# Génération du chemin S3
sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;
    
    my $prefix = $scfg->{prefix} // 'proxmox/';
    $prefix =~ s|/+$|/|; # Assure qu'il y a un slash final
    
    my $path;
    if ($snapname) {
        $path = "${prefix}snapshots/${volname}/${snapname}";
    } else {
        $path = "${prefix}${volname}";
    }
    
    return ($scfg->{bucket}, $path);
}

# Activation du stockage
sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    
    # Vérification de la connectivité
    eval {
        $s3_client->test_connection();
    };
    if ($@) {
        die "Cannot connect to S3 storage '$storeid': $@";
    }
    
    # Vérification du bucket
    eval {
        $s3_client->head_bucket($scfg->{bucket});
    };
    if ($@) {
        if ($@ =~ /NoSuchBucket/) {
            # Tentative de création du bucket
            eval {
                $s3_client->create_bucket($scfg->{bucket});
                PVE::Storage::S3::Utils::log_info("Created bucket $scfg->{bucket}");
            };
            if ($@) {
                die "Cannot create bucket '$scfg->{bucket}': $@";
            }
        } else {
            die "Cannot access bucket '$scfg->{bucket}': $@";
        }
    }
    
    # Configuration du cycle de vie si activé
    if ($scfg->{lifecycle_enabled}) {
        $class->configure_lifecycle($s3_client, $scfg);
    }
    
    return 1;
}

# Configuration du cycle de vie
sub configure_lifecycle {
    my ($class, $s3_client, $scfg) = @_;
    
    my $lifecycle_config = {
        Rules => [
            {
                ID => 'proxmox-lifecycle',
                Status => 'Enabled',
                Filter => {
                    Prefix => $scfg->{prefix} // 'proxmox/',
                },
                Transitions => [],
            }
        ]
    };
    
    if ($scfg->{transition_days}) {
        push @{$lifecycle_config->{Rules}->[0]->{Transitions}}, {
            Days => $scfg->{transition_days},
            StorageClass => 'STANDARD_IA',
        };
    }
    
    if ($scfg->{glacier_days}) {
        push @{$lifecycle_config->{Rules}->[0]->{Transitions}}, {
            Days => $scfg->{glacier_days},
            StorageClass => 'GLACIER',
        };
    }
    
    eval {
        $s3_client->put_bucket_lifecycle($scfg->{bucket}, $lifecycle_config);
    };
    if ($@) {
        PVE::Storage::S3::Utils::log_warn("Cannot configure lifecycle: $@");
    }
}

# Liste des images/backups
sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    my $prefix = $scfg->{prefix} // 'proxmox/';
    
    my $res = [];
    
    eval {
        my $objects = $s3_client->list_objects($scfg->{bucket}, $prefix);
        
        foreach my $object (@$objects) {
            my $key = $object->{Key};
            next if !defined($key) || $key eq $prefix; # Skip dossiers
            
            # Supprime le préfixe pour obtenir le nom du volume
            my $volname = $key;
            $volname =~ s/^\Q$prefix\E//;
            
            # Parse le nom du fichier
            if ($volname =~ /^backup\//) {
                # C'est un backup
                if ($volname =~ /^backup\/vzdump-(\w+)-(\d+)-(\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2})\.(\w+)(?:\.(\w+))?$/) {
                    my ($format, $vmid_found, $timestamp, $ext, $compress) = ($1, $2, $3, $4, $5);
                    
                    next if $vmid && $vmid ne $vmid_found;
                    
                    my $volid = "$storeid:backup/$volname";
                    push @$res, {
                        volid => $volid,
                        format => $format,
                        size => $object->{Size},
                        vmid => $vmid_found,
                        ctime => PVE::Storage::S3::Utils::parse_s3_time($object->{LastModified}),
                    };
                }
            } else {
                # Autres types de contenu (ISO, templates, etc.)
                my $volid = "$storeid:$volname";
                push @$res, {
                    volid => $volid,
                    size => $object->{Size},
                    ctime => PVE::Storage::S3::Utils::parse_s3_time($object->{LastModified}),
                };
            }
        }
    };
    if ($@) {
        die "Cannot list S3 objects: $@";
    }
    
    return $res;
}

# Statut du stockage
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    
    eval {
        $s3_client->test_connection();
    };
    if ($@) {
        return (0, 0, 0, 0); # total, free, used, active
    }
    
    # Pour S3, on considère l'espace comme "illimité"
    # mais on peut récupérer des métriques via CloudWatch
    my $total = 1024 * 1024 * 1024 * 1024 * 1024; # 1PB symbolique
    my $used = 0;
    
    # Calcul de l'espace utilisé en listant les objets
    eval {
        my $objects = $s3_client->list_objects($scfg->{bucket}, $scfg->{prefix});
        $used = 0;
        foreach my $object (@$objects) {
            $used += $object->{Size} // 0;
        }
    };
    
    my $free = $total - $used;
    my $active = 1;
    
    return ($total, $free, $used, $active);
}

# Allocation d'une image
sub alloc_image {
    my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;
    
    die "Unsupported format '$fmt'" if $fmt ne 'raw' && $fmt ne 'qcow2';
    
    my $volname = $name;
    if (!$volname) {
        $volname = "vm-$vmid-disk-" . int(rand(10000));
    }
    $volname .= ".$fmt" if $volname !~ /\.$fmt$/;
    
    my $volid = "$storeid:$volname";
    
    # Création d'un fichier temporaire vide pour réserver l'espace
    my ($bucket, $key) = $class->path($scfg, $volname, $storeid);
    my $s3_client = $class->get_s3_client($scfg);
    
    eval {
        # Créer un fichier sparse temporaire
        my $temp_file = "/tmp/pve-s3-sparse-$vmid-" . int(rand(10000));
        run_command(['truncate', '-s', $size, $temp_file]);
        
        # Upload vers S3
        $s3_client->upload_file($temp_file, $bucket, $key, {
            content_type => 'application/octet-stream',
            metadata => {
                'x-pve-vmid' => $vmid,
                'x-pve-format' => $fmt,
                'x-pve-size' => $size,
                'x-pve-created' => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime()),
            },
        });
        
        unlink $temp_file;
    };
    if ($@) {
        die "Cannot allocate image '$volname': $@";
    }
    
    return $volid;
}

# Libération d'une image
sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase) = @_;
    
    my ($bucket, $key) = $class->path($scfg, $volname, $storeid);
    my $s3_client = $class->get_s3_client($scfg);
    
    eval {
        $s3_client->delete_object($bucket, $key);
    };
    if ($@) {
        die "Cannot delete image '$volname': $@";
    }
    
    return undef;
}

# Clone d'une image
sub clone_image {
    my ($class, $scfg, $storeid, $volname, $vmid, $snap) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    my ($bucket, $source_key) = $class->path($scfg, $volname, $storeid, $snap);
    
    # Génération du nom de destination
    my $clone_name = "vm-$vmid-disk-" . int(rand(10000));
    if ($volname =~ /\.(\w+)$/) {
        $clone_name .= ".$1";
    }
    
    my ($dest_bucket, $dest_key) = $class->path($scfg, $clone_name, $storeid);
    
    eval {
        $s3_client->copy_object($bucket, $source_key, $dest_bucket, $dest_key, {
            metadata_directive => 'REPLACE',
            metadata => {
                'x-pve-vmid' => $vmid,
                'x-pve-cloned-from' => $volname,
                'x-pve-cloned-at' => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime()),
            },
        });
    };
    if ($@) {
        die "Cannot clone image '$volname': $@";
    }
    
    return "$storeid:$clone_name";
}

# Informations sur les archives de backup
sub archive_info {
    my ($class, $scfg, $volname) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    my ($bucket, $key) = $class->path($scfg, $volname, undef);
    
    my $info = {};
    
    eval {
        my $metadata = $s3_client->get_object_metadata($bucket, $key);
        
        $info->{type} = $metadata->{'x-pve-backup-type'} // 'unknown';
        $info->{vmid} = $metadata->{'x-pve-vmid'};
        $info->{size} = $metadata->{ContentLength};
        $info->{ctime} = PVE::Storage::S3::Utils::parse_s3_time($metadata->{LastModified});
        
        # Extraction du type et format depuis le nom de fichier
        if ($volname =~ /vzdump-(\w+)-(\d+)-.*\.(\w+)(?:\.(\w+))?$/) {
            $info->{type} = $1;
            $info->{vmid} = $2;
            $info->{format} = $3;
            $info->{compression} = $4 if $4;
        }
    };
    if ($@) {
        die "Cannot get archive info for '$volname': $@";
    }
    
    return $info;
}

# Extraction de la config depuis un backup
sub extract_vzdump_config {
    my ($class, $scfg, $volname) = @_;
    
    my $s3_client = $class->get_s3_client($scfg);
    my ($bucket, $key) = $class->path($scfg, $volname, undef);
    
    # Télécharge temporairement le début du fichier pour extraire la config
    my $temp_file = "/tmp/pve-s3-extract-" . int(rand(10000));
    
    eval {
        # Télécharge seulement les premiers 64KB
        $s3_client->download_range($bucket, $key, $temp_file, 0, 65536);
        
        # Extraction de la config selon le format
        my $config = '';
        if ($volname =~ /\.tar\./) {
            # Format tar
            $config = `tar -xOf $temp_file qemu-server.conf 2>/dev/null || tar -xOf $temp_file pct.conf 2>/dev/null`;
        } elsif ($volname =~ /\.vma\./) {
            # Format VMA
            $config = `vma config $temp_file 2>/dev/null`;
        }
        
        unlink $temp_file;
        
        return $config;
    };
    if ($@) {
        unlink $temp_file if -f $temp_file;
        die "Cannot extract config from '$volname': $@";
    }
}

# Enregistrement du plugin
PVE::Storage::Plugin::register_plugin(__PACKAGE__);

1;
```

### 2. Client S3 (S3/Client.pm)

```perl
package PVE::Storage::S3::Client;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use URI;
use JSON;
use Digest::SHA qw(hmac_sha256_hex hmac_sha256);
use MIME::Base64 qw(encode_base64 decode_base64);
use POSIX qw(strftime);
use Time::HiRes qw(time);
use File::Temp qw(tempfile);
use PVE::Storage::S3::Utils;

sub new {
    my ($class, $config, $auth) = @_;
    
    my $self = {
        config => $config,
        auth => $auth,
        ua => LWP::UserAgent->new(
            timeout => $config->{connection_timeout},
            agent => 'Proxmox-S3-Plugin/1.0',
        ),
    };
    
    return bless $self, $class;
}

# Test de connectivité
sub test_connection {
    my ($self) = @_;
    
    my $request = $self->_create_request('HEAD', '/', {});
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Connection test failed: " . $response->status_line;
    }
    
    return 1;
}

# Vérification de l'existence d'un bucket
sub head_bucket {
    my ($self, $bucket) = @_;
    
    my $request = $self->_create_request('HEAD', "/$bucket", {});
    my $response = $self->{ua}->request($request);
    
    if ($response->code == 404) {
        die "NoSuchBucket: The specified bucket does not exist";
    } elsif (!$response->is_success) {
        die "Error checking bucket: " . $response->status_line;
    }
    
    return $response->headers;
}

# Création d'un bucket
sub create_bucket {
    my ($self, $bucket) = @_;
    
    my $content = '';
    if ($self->{config}->{region} && $self->{config}->{region} ne 'us-east-1') {
        $content = qq{<?xml version="1.0" encoding="UTF-8"?>
<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <LocationConstraint>$self->{config}->{region}</LocationConstraint>
</CreateBucketConfiguration>};
    }
    
    my $request = $self->_create_request('PUT', "/$bucket", {
        'Content-Type' => 'application/xml',
        'Content-Length' => length($content),
    }, $content);
    
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Cannot create bucket: " . $response->status_line;
    }
    
    return 1;
}

# Liste des objets dans un bucket
sub list_objects {
    my ($self, $bucket, $prefix, $max_keys) = @_;
    
    $max_keys //= 1000;
    my $objects = [];
    my $continuation_token = '';
    
    do {
        my $params = {
            'prefix' => $prefix,
            'max-keys' => $max_keys,
        };
        $params->{'continuation-token'} = $continuation_token if $continuation_token;
        
        my $query_string = join('&', map { 
            "$_=" . URI::Escape::uri_escape($params->{$_}) 
        } keys %$params);
        
        my $request = $self->_create_request('GET', "/$bucket?$query_string", {});
        my $response = $self->{ua}->request($request);
        
        if (!$response->is_success) {
            die "Cannot list objects: " . $response->status_line;
        }
        
        # Parse XML response
        my $xml_content = $response->content;
        my $parsed = $self->_parse_list_objects_xml($xml_content);
        
        push @$objects, @{$parsed->{objects}};
        $continuation_token = $parsed->{next_continuation_token} // '';
        
    } while ($continuation_token);
    
    return $objects;
}

# Upload d'un fichier
sub upload_file {
    my ($self, $file_path, $bucket, $key, $options) = @_;
    
    $options //= {};
    
    my $file_size = -s $file_path;
    my $chunk_size = $self->{config}->{multipart_chunk_size};
    
    if ($file_size > $chunk_size) {
        return $self->_multipart_upload($file_path, $bucket, $key, $options);
    } else {
        return $self->_single_upload($file_path, $bucket, $key, $options);
    }
}

# Upload simple
sub _single_upload {
    my ($self, $file_path, $bucket, $key, $options) = @_;
    
    open my $fh, '<:raw', $file_path or die "Cannot open file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    my $headers = {
        'Content-Type' => $options->{content_type} // 'application/octet-stream',
        'Content-Length' => length($content),
        'Content-MD5' => encode_base64(Digest::MD5::md5($content), ''),
    };
    
    # Ajout des métadonnées
    if ($options->{metadata}) {
        foreach my $key_meta (keys %{$options->{metadata}}) {
            $headers->{"x-amz-meta-$key_meta"} = $options->{metadata}->{$key_meta};
        }
    }
    
    # Encryption
    if ($self->{config}->{server_side_encryption}) {
        $headers->{'x-amz-server-side-encryption'} = $self->{config}->{server_side_encryption};
        if ($self->{config}->{kms_key_id}) {
            $headers->{'x-amz-server-side-encryption-aws-kms-key-id'} = $self->{config}->{kms_key_id};
        }
    }
    
    # Storage class
    if ($self->{config}->{storage_class}) {
        $headers->{'x-amz-storage-class'} = $self->{config}->{storage_class};
    }
    
    my $request = $self->_create_request('PUT', "/$bucket/$key", $headers, $content);
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Upload failed: " . $response->status_line;
    }
    
    return {
        etag => $response->header('ETag'),
        version_id => $response->header('x-amz-version-id'),
    };
}

# Upload multipart
sub _multipart_upload {
    my ($self, $file_path, $bucket, $key, $options) = @_;
    
    my $file_size = -s $file_path;
    my $chunk_size = $self->{config}->{multipart_chunk_size};
    my $total_chunks = int(($file_size + $chunk_size - 1) / $chunk_size);
    
    PVE::Storage::S3::Utils::log_info("Starting multipart upload: $total_chunks chunks");
    
    # Initiation du multipart upload
    my $upload_id = $self->_initiate_multipart_upload($bucket, $key, $options);
    
    my @parts = ();
    my $uploaded = 0;
    
    eval {
        open my $fh, '<:raw', $file_path or die "Cannot open file: $!";
        
        for my $part_number (1..$total_chunks) {
            my $chunk_data;
            my $bytes_read = read($fh, $chunk_data, $chunk_size);
            last if $bytes_read == 0;
            
            my $etag = $self->_upload_part($bucket, $key, $upload_id, $part_number, $chunk_data);
            push @parts, {
                PartNumber => $part_number,
                ETag => $etag,
            };
            
            $uploaded += $bytes_read;
            my $progress = int(($uploaded / $file_size) * 100);
            PVE::Storage::S3::Utils::log_info("Upload progress: $progress% ($uploaded/$file_size bytes)");
        }
        
        close $fh;
        
        # Finalisation du multipart upload
        $self->_complete_multipart_upload($bucket, $key, $upload_id, \@parts);
        
    };
    if ($@) {
        # Annulation du multipart upload en cas d'erreur
        eval {
            $self->_abort_multipart_upload($bucket, $key, $upload_id);
        };
        die "Multipart upload failed: $@";
    }
    
    PVE::Storage::S3::Utils::log_info("Multipart upload completed successfully");
    
    return { upload_id => $upload_id };
}

# Initiation multipart upload
sub _initiate_multipart_upload {
    my ($self, $bucket, $key, $options) = @_;
    
    my $headers = {
        'Content-Type' => $options->{content_type} // 'application/octet-stream',
    };
    
    # Métadonnées et options
    if ($options->{metadata}) {
        foreach my $meta_key (keys %{$options->{metadata}}) {
            $headers->{"x-amz-meta-$meta_key"} = $options->{metadata}->{$meta_key};
        }
    }
    
    if ($self->{config}->{server_side_encryption}) {
        $headers->{'x-amz-server-side-encryption'} = $self->{config}->{server_side_encryption};
    }
    
    if ($self->{config}->{storage_class}) {
        $headers->{'x-amz-storage-class'} = $self->{config}->{storage_class};
    }
    
    my $request = $self->_create_request('POST', "/$bucket/$key?uploads", $headers);
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Cannot initiate multipart upload: " . $response->status_line;
    }
    
    # Parse XML pour récupérer l'upload ID
    my $xml = $response->content;
    if ($xml =~ /<UploadId>([^<]+)<\/UploadId>/) {
        return $1;
    } else {
        die "Cannot parse upload ID from response";
    }
}

# Upload d'une part
sub _upload_part {
    my ($self, $bucket, $key, $upload_id, $part_number, $data) = @_;
    
    my $headers = {
        'Content-Type' => 'application/octet-stream',
        'Content-Length' => length($data),
        'Content-MD5' => encode_base64(Digest::MD5::md5($data), ''),
    };
    
    my $url = "/$bucket/$key?partNumber=$part_number&uploadId=$upload_id";
    my $request = $self->_create_request('PUT', $url, $headers, $data);
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Cannot upload part $part_number: " . $response->status_line;
    }
    
    my $etag = $response->header('ETag');
    $etag =~ s/"//g; # Supprime les guillemets
    
    return $etag;
}

# Finalisation multipart upload
sub _complete_multipart_upload {
    my ($self, $bucket, $key, $upload_id, $parts) = @_;
    
    # Génération du XML pour completion
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>
<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">};
    
    foreach my $part (@$parts) {
        $xml .= qq{
<Part>
    <ETag>"$part->{ETag}"</ETag>
    <PartNumber>$part->{PartNumber}</PartNumber>
</Part>};
    }
    
    $xml .= qq{
</CompleteMultipartUpload>};
    
    my $headers = {
        'Content-Type' => 'application/xml',
        'Content-Length' => length($xml),
    };
    
    my $url = "/$bucket/$key?uploadId=$upload_id";
    my $request = $self->_create_request('POST', $url, $headers, $xml);
    my $response = $self->{ua}->request($request);
    
    if (!$response->is_success) {
        die "Cannot complete multipart upload: " . $response->status_line;
    }
    
    return 1;
}

# Création de la signature AWS4
sub _create_request {
    my ($self, $method, $path, $headers, $content) = @_;
    
    $headers //= {};
    $content //= '';
    
    my $uri = URI->new($self->{config}->{endpoint} . $path);
    
    # Ajout des headers obligatoires
    $headers->{'Host'} = $uri->host;
    $headers->{'x-amz-date'} = strftime('%Y%m%dT%H%M%SZ', gmtime());
    $headers->{'x-amz-content-sha256'} = Digest::SHA::sha256_hex($content);
    
    # Ajout du token de session si présent
    if ($self->{auth}->{session_token}) {
        $headers->{'x-amz-security-token'} = $self->{auth}->{session_token};
    }
    
    # Création de la signature
    my $authorization = $self->_create_aws4_signature($method, $uri, $headers, $content);
    $headers->{'Authorization'} = $authorization;
    
    # Création de la requête HTTP
    my $request = HTTP::Request->new($method, $uri);
    
    foreach my $header_name (keys %$headers) {
        $request->header($header_name => $headers->{$header_name});
    }
    
    $request->content($content) if $content;
    
    return $request;
}

# Signature AWS4
sub _create_aws4_signature {
    my ($self, $method, $uri, $headers, $content) = @_;
    
    my $region = $self->{config}->{region};
    my $service = 's3';
    my $date = $headers->{'x-amz-date'};
    my $date_short = substr($date, 0, 8);
    
    # Canonical request
    my $canonical_uri = $uri->path;
    my $canonical_query = $uri->query // '';
    
    # Canonical headers (triés)
    my @header_names = sort { lc($a) cmp lc($b) } keys %$headers;
    my $canonical_headers = '';
    my $signed_headers = '';
    
    foreach my $header_name (@header_names) {
        next if $header_name !~ /^(host|x-amz-|content-type|content-md5)$/i;
        $canonical_headers .= lc($header_name) . ':' . $headers->{$header_name} . "\n";
        $signed_headers .= lc($header_name) . ';';
    }
    $signed_headers =~ s/;$//;
    
    my $payload_hash = $headers->{'x-amz-content-sha256'};
    
    my $canonical_request = join("\n",
        $method,
        $canonical_uri,
        $canonical_query,
        $canonical_headers,
        $signed_headers,
        $payload_hash
    );
    
    # String to sign
    my $algorithm = 'AWS4-HMAC-SHA256';
    my $credential_scope = "$date_short/$region/$service/aws4_request";
    my $string_to_sign = join("\n",
        $algorithm,
        $date,
        $credential_scope,
        Digest::SHA::sha256_hex($canonical_request)
    );
    
    # Signing key
    my $k_date = hmac_sha256($date_short, 'AWS4' . $self->{auth}->{secret_key});
    my $k_region = hmac_sha256($region, $k_date);
    my $k_service = hmac_sha256($service, $k_region);
    my $k_signing = hmac_sha256('aws4_request', $k_service);
    
    # Signature
    my $signature = hmac_sha256_hex($string_to_sign, $k_signing);
    
    # Authorization header
    my $credential = $self->{auth}->{access_key} . '/' . $credential_scope;
    my $authorization = "$algorithm Credential=$credential, SignedHeaders=$signed_headers, Signature=$signature";
    
    return $authorization;
}

# Parser XML simple pour list objects
sub _parse_list_objects_xml {
    my ($self, $xml) = @_;
    
    my $objects = [];
    my $next_token = '';
    
    # Parse XML basique (pour éviter les dépendances)
    while ($xml =~ /<Contents>(.*?)<\/Contents>/gs) {
        my $content = $1;
        my $object = {};
        
        if ($content =~ /<Key>([^<]+)<\/Key>/) {
            $object->{Key} = $1;
        }
        if ($content =~ /<Size>(\d+)<\/Size>/) {
            $object->{Size} = $1;
        }
        if ($content =~ /<LastModified>([^<]+)<\/LastModified>/) {
            $object->{LastModified} = $1;
        }
        if ($content =~ /<ETag>"?([^<"]+)"?<\/ETag>/) {
            $object->{ETag} = $1;
        }
        
        push @$objects, $object if $object->{Key};
    }
    
    if ($xml =~ /<NextContinuationToken>([^<]+)<\/NextContinuationToken>/) {
        $next_token = $1;
    }
    
    return {
        objects => $objects,
        next_continuation_token => $next_token,
    };
}

1;
```

### 3. Utilitaires (S3/Utils.pm)

```perl
package PVE::Storage::S3::Utils;

use strict;
use warnings;
use POSIX qw(strftime);
use Time::Local;
use Exporter qw(import);

our @EXPORT_OK = qw(log_info log_warn log_error parse_s3_time format_bytes);

my $LOG_FILE = '/var/log/pve/storage-s3.log';

sub log_message {
    my ($level, $message) = @_;
    
    my $timestamp = strftime('%Y-%m-%d %H:%M:%S', localtime());
    my $log_line = "[$timestamp] [$level] $message\n";
    
    if (open my $fh, '>>', $LOG_FILE) {
        print $fh $log_line;
        close $fh;
    }
    
    # Log vers syslog aussi
    system('logger', '-t', 'pve-s3-storage', "[$level] $message");
}

sub log_info {
    my ($message) = @_;
    log_message('INFO', $message);
}

sub log_warn {
    my ($message) = @_;
    log_message('WARN', $message);
}

sub log_error {
    my ($message) = @_;
    log_message('ERROR', $message);
}

# Parse timestamp S3 format
sub parse_s3_time {
    my ($s3_time) = @_;
    
    # Format: 2023-12-25T14:30:45.000Z
    if ($s3_time =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/) {
        my ($year, $month, $day, $hour, $min, $sec) = ($1, $2, $3, $4, $5, $6);
        return timelocal($sec, $min, $hour, $day, $month - 1, $year);
    }
    
    return 0;
}

# Formatage des tailles
sub format_bytes {
    my ($bytes) = @_;
    
    my @units = qw(B KB MB GB TB PB);
    my $unit_index = 0;
    
    while ($bytes >= 1024 && $unit_index < @units - 1) {
        $bytes /= 1024;
        $unit_index++;
    }
    
    return sprintf("%.2f %s", $bytes, $units[$unit_index]);
}

1;
```

## Intégration dans Proxmox

### 1. Installation et Enregistrement

```bash
#!/bin/bash
# Script d'installation du plugin S3

# Copie des fichiers
cp S3Plugin.pm /usr/share/perl5/PVE/Storage/
mkdir -p /usr/share/perl5/PVE/Storage/S3/
cp S3/*.pm /usr/share/perl5/PVE/Storage/S3/

# Permissions
chmod 644 /usr/share/perl5/PVE/Storage/S3Plugin.pm
chmod 644 /usr/share/perl5/PVE/Storage/S3/*.pm

# Redémarrage des services Proxmox
systemctl restart pvedaemon
systemctl restart pvestatd
systemctl restart pveproxy

# Vérification
pvesm help | grep -i s3
```

### 2. Configuration dans storage.cfg

```perl
# Configuration basique
s3: s3-backup
    endpoint https://s3.amazonaws.com
    region us-east-1
    bucket my-proxmox-backups
    access_key AKIAIOSFODNN7EXAMPLE
    secret_key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    prefix proxmox/
    content backup
    maxfiles 10
    
# Configuration avancée avec chiffrement
s3: s3-encrypted
    endpoint https://s3.eu-west-1.amazonaws.com
    region eu-west-1
    bucket encrypted-proxmox-storage
    access_key AKIAIOSFODNN7EXAMPLE
    secret_key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    prefix vms/
    content images,rootdir
    server_side_encryption aws:kms
    kms_key_id arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012
    storage_class STANDARD_IA
    multipart_chunk_size 500
    max_concurrent_uploads 5
    lifecycle_enabled 1
    transition_days 30
    glacier_days 365

# Configuration MinIO compatible
s3: minio-storage
    endpoint https://minio.example.com:9000
    region us-east-1
    bucket proxmox
    access_key minio_access_key
    secret_key minio_secret_key
    prefix pve/
    content backup,iso,vztmpl
```

## Configuration et Déploiement

### 1. Script d'Installation Automatisée

```bash
#!/bin/bash
# install-s3-plugin.sh

set -e

PLUGIN_VERSION="1.0.0"
INSTALL_DIR="/usr/share/perl5/PVE/Storage"
LOG_FILE="/var/log/pve-s3-plugin-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting S3 Plugin installation v$PLUGIN_VERSION"

# Vérification des prérequis
if ! command -v pvesm >/dev/null 2>&1; then
    log "ERROR: Proxmox VE not found"
    exit 1
fi

# Installation des dépendances Perl
log "Installing Perl dependencies..."
apt-get update
apt-get install -y \
    libwww-perl \
    libjson-perl \
    libdigest-sha-perl \
    libmime-base64-perl \
    liburi-perl \
    libxml-simple-perl

# Sauvegarde des fichiers existants
if [ -f "$INSTALL_DIR/S3Plugin.pm" ]; then
    log "Backing up existing S3 plugin..."
    cp "$INSTALL_DIR/S3Plugin.pm" "$INSTALL_DIR/S3Plugin.pm.backup.$(date +%s)"
fi

# Installation des fichiers du plugin
log "Installing plugin files..."
mkdir -p "$INSTALL_DIR/S3"

# Copie des fichiers (assumant qu'ils sont dans le répertoire courant)
cp S3Plugin.pm "$INSTALL_DIR/"
cp S3/*.pm "$INSTALL_DIR/S3/"

# Définition des permissions
chmod 644 "$INSTALL_DIR/S3Plugin.pm"
chmod 644 "$INSTALL_DIR/S3"/*.pm
chmod 755 "$INSTALL_DIR/S3"

# Création des répertoires de logs
mkdir -p /var/log/pve
touch /var/log/pve/storage-s3.log
chmod 640 /var/log/pve/storage-s3.log

# Installation des scripts utilitaires
log "Installing utility scripts..."
cat > /usr/local/bin/pve-s3-backup << 'EOF'
#!/bin/bash
# Script de backup vers S3
STORAGE_ID="$1"
VMID="$2"
TARGET_FILE="$3"

if [ -z "$STORAGE_ID" ] || [ -z "$VMID" ]; then
    echo "Usage: $0 <storage_id> <vmid> [target_file]"
    exit 1
fi

vzdump "$VMID" --storage "$STORAGE_ID" --mode snapshot --compress gzip ${TARGET_FILE:+--dumpdir "$TARGET_FILE"}
EOF

chmod +x /usr/local/bin/pve-s3-backup

# Configuration logrotate
cat > /etc/logrotate.d/pve-s3-storage << 'EOF'
/var/log/pve/storage-s3.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root adm
}
EOF

# Test de la syntaxe Perl
log "Testing Perl syntax..."
if ! perl -c "$INSTALL_DIR/S3Plugin.pm" >/dev/null 2>&1; then
    log "ERROR: Syntax error in S3Plugin.pm"
    exit 1
fi

# Redémarrage des services Proxmox
log "Restarting Proxmox services..."
systemctl restart pvedaemon
systemctl restart pvestatd
systemctl restart pveproxy

# Attente que les services redémarrent
sleep 5

# Vérification de l'installation
log "Verifying installation..."
if pvesm help 2>&1 | grep -q "s3"; then
    log "SUCCESS: S3 plugin installed successfully"
else
    log "WARNING: Plugin may not be properly registered"
fi

log "Installation completed. Check $LOG_FILE for details."
log "You can now configure S3 storage in /etc/pve/storage.cfg"

echo ""
echo "Example configuration:"
echo "s3: my-s3-storage"
echo "    endpoint https://s3.amazonaws.com"
echo "    region us-east-1"
echo "    bucket my-bucket"
echo "    access_key YOUR_ACCESS_KEY"
echo "    secret_key YOUR_SECRET_KEY"
echo "    content backup"
```

### 2. Configuration des Credentials

```bash
#!/bin/bash
# configure-s3-credentials.sh

CRED_DIR="/etc/pve/s3-credentials"
mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"

# Configuration interactive
read -p "Enter S3 endpoint URL: " ENDPOINT
read -p "Enter AWS region [us-east-1]: " REGION
REGION=${REGION:-us-east-1}
read -p "Enter bucket name: " BUCKET
read -p "Enter access key: " ACCESS_KEY
read -s -p "Enter secret key: " SECRET_KEY
echo

# Génération du fichier de configuration
cat > "$CRED_DIR/s3-config.json" << EOF
{
    "endpoint": "$ENDPOINT",
    "region": "$REGION", 
    "bucket": "$BUCKET",
    "access_key": "$ACCESS_KEY",
    "secret_key": "$SECRET_KEY",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chmod 600 "$CRED_DIR/s3-config.json"

# Test de connectivité
echo "Testing S3 connection..."
if curl -s --head "$ENDPOINT" >/dev/null; then
    echo "✓ S3 endpoint is reachable"
else
    echo "✗ Warning: S3 endpoint may not be reachable"
fi

echo "Configuration saved to $CRED_DIR/s3-config.json"
```

## API et Interfaces

### 1. Interface Web Proxmox

```javascript
// Ajout du plugin S3 dans l'interface web Proxmox
// Fichier: www/manager6/storage/S3Edit.js

Ext.define('PVE.storage.S3InputPanel', {
    extend: 'PVE.panel.StorageBase',
    
    initComponent: function() {
        var me = this;

        me.column1 = [
            {
                xtype: 'pvetextfield',
                name: 'endpoint',
                fieldLabel: gettext('S3 Endpoint'),
                allowBlank: false,
                listeners: {
                    change: function(field, value) {
                        if (value.match(/amazonaws\.com/)) {
                            me.down('field[name=region]').setVisible(true);
                        }
                    }
                }
            },
            {
                xtype: 'pvetextfield', 
                name: 'bucket',
                fieldLabel: gettext('Bucket'),
                allowBlank: false
            },
            {
                xtype: 'pvetextfield',
                name: 'region', 
                fieldLabel: gettext('Region'),
                value: 'us-east-1',
                allowBlank: false
            }
        ];

        me.column2 = [
            {
                xtype: 'pvetextfield',
                name: 'access_key',
                fieldLabel: gettext('Access Key'),
                allowBlank: false
            },
            {
                xtype: 'pvetextfield',
                name: 'secret_key',
                fieldLabel: gettext('Secret Key'),
                inputType: 'password',
                allowBlank: false
            },
            {
                xtype: 'pvetextfield',
                name: 'prefix',
                fieldLabel: gettext('Prefix'),
                value: 'proxmox/',
                emptyText: 'proxmox/'
            }
        ];

        me.columnB = [
            {
                xtype: 'pveComboBox',
                name: 'storage_class',
                fieldLabel: gettext('Storage Class'),
                value: 'STANDARD',
                comboItems: [
                    ['STANDARD', 'Standard'],
                    ['STANDARD_IA', 'Standard IA'],
                    ['ONEZONE_IA', 'One Zone IA'],
                    ['REDUCED_REDUNDANCY', 'Reduced Redundancy'],
                    ['GLACIER', 'Glacier'],
                    ['DEEP_ARCHIVE', 'Deep Archive'],
                    ['INTELLIGENT_TIERING', 'Intelligent Tiering']
                ]
            },
            {
                xtype: 'pveComboBox',
                name: 'server_side_encryption',
                fieldLabel: gettext('Encryption'),
                comboItems: [
                    ['', 'None'],
                    ['AES256', 'AES256'],
                    ['aws:kms', 'AWS KMS']
                ],
                listeners: {
                    change: function(field, value) {
                        var kmsField = me.down('field[name=kms_key_id]');
                        kmsField.setVisible(value === 'aws:kms');
                        kmsField.setDisabled(value !== 'aws:kms');
                    }
                }
            },
            {
                xtype: 'pvetextfield',
                name: 'kms_key_id',
                fieldLabel: gettext('KMS Key ID'),
                hidden: true,
                disabled: true
            }
        ];

        me.callParent();
    }
});

// Enregistrement du panel
Ext.define('PVE.storage.S3Edit', {
    extend: 'PVE.window.Edit',
    
    initComponent: function() {
        var me = this;
        
        me.subject = gettext('S3 Storage');
        me.items = [{
            xtype: 'pveS3InputPanel',
            baseurl: me.baseurl,
            url: me.url,
            useTypeInUrl: me.useTypeInUrl
        }];
        
        me.callParent();
    }
});
```

### 2. API REST Extensions

```perl
# Extension de l'API REST pour les opérations S3 spécifiques
package PVE::API2::Storage::S3;

use strict;
use warnings;
use PVE::Storage::S3Plugin;
use PVE::RESTHandler;
use PVE::JSONSchema qw(get_standard_option);
use PVE::API2::Storage::Config;

use base qw(PVE::RESTHandler);

# Test de connectivité S3
__PACKAGE__->register_method({
    name => 'test_connection',
    path => 'test-connection', 
    method => 'POST',
    description => "Test S3 storage connection",
    parameters => {
        additionalProperties => 0,
        properties => {
            storage => get_standard_option('pve-storage-id'),
        },
    },
    returns => {
        type => 'object',
        properties => {
            success => { type => 'boolean' },
            message => { type => 'string', optional => 1 },
            latency => { type => 'number', optional => 1 },
        },
    },
    code => sub {
        my ($param) = @_;
        
        my $cfg = PVE::Storage::config();
        my $scfg = PVE::Storage::storage_config($cfg, $param->{storage});
        
        die "Storage '$param->{storage}' is not an S3 storage\n" 
            if $scfg->{type} ne 's3';
            
        my $start_time = time();
        
        eval {
            my $s3_client = PVE::Storage::S3Plugin->get_s3_client($scfg);
            $s3_client->test_connection();
        };
        
        my $latency = time() - $start_time;
        
        if ($@) {
            return {
                success => 0,
                message => "$@",
                latency => $latency,
            };
        } else {
            return {
                success => 1,
                message => "Connection successful",
                latency => $latency,
            };
        }
    }
});

# Informations détaillées sur le bucket
__PACKAGE__->register_method({
    name => 'bucket_info',
    path => 'bucket-info',
    method => 'GET', 
    description => "Get S3 bucket information",
    parameters => {
        additionalProperties => 0,
        properties => {
            storage => get_standard_option('pve-storage-id'),
        },
    },
    returns => {
        type => 'object',
        properties => {
            name => { type => 'string' },
            region => { type => 'string' },
            creation_date => { type => 'string' },
            object_count => { type => 'integer' },
            total_size => { type => 'integer' },
            storage_classes => { type => 'object' },
        },
    },
    code => sub {
        my ($param) = @_;
        
        my $cfg = PVE::Storage::config();
        my $scfg = PVE::Storage::storage_config($cfg, $param->{storage});
        
        die "Storage '$param->{storage}' is not an S3 storage\n" 
            if $scfg->{type} ne 's3';
            
        my $s3_client = PVE::Storage::S3Plugin->get_s3_client($scfg);
        
        # Récupération des informations du bucket
        my $bucket_info = $s3_client->get_bucket_info($scfg->{bucket});
        
        return $bucket_info;
    }
});

1;
```

## Gestion des Erreurs

### 1. Système de Gestion d'Erreurs

```perl
package PVE::Storage::S3::Exception;

use strict;
use warnings;
use overload '""' => \&as_string;

# Types d'erreurs S3
use constant {
    ERROR_CONNECTION => 'CONNECTION_ERROR',
    ERROR_AUTHENTICATION => 'AUTH_ERROR', 
    ERROR_PERMISSION => 'PERMISSION_ERROR',
    ERROR_NOT_FOUND => 'NOT_FOUND',
    ERROR_QUOTA => 'QUOTA_EXCEEDED',
    ERROR_NETWORK => 'NETWORK_ERROR',
    ERROR_SERVER => 'SERVER_ERROR',
    ERROR_CLIENT => 'CLIENT_ERROR',
    ERROR_TIMEOUT => 'TIMEOUT_ERROR',
};

sub new {
    my ($class, $type, $message, $details) = @_;
    
    my $self = {
        type => $type,
        message => $message,
        details => $details // {},
        timestamp => time(),
        trace => _get_stack_trace(),
    };
    
    return bless $self, $class;
}

sub as_string {
    my ($self) = @_;
    return "[$self->{type}] $self->{message}";
}

sub _get_stack_trace {
    my @trace;
    my $i = 1;
    
    while (my ($package, $filename, $line, $subroutine) = caller($i++)) {
        push @trace, {
            package => $package,
            filename => $filename,  
            line => $line,
            subroutine => $subroutine,
        };
        last if $i > 10; # Limite la trace
    }
    
    return \@trace;
}

# Factory methods pour les erreurs courantes
sub connection_error {
    my ($class, $message, $details) = @_;
    return $class->new(ERROR_CONNECTION, $message, $details);
}

sub auth_error {
    my ($class, $message, $details) = @_;
    return $class->new(ERROR_AUTHENTICATION, $message, $details);
}

sub permission_error {
    my ($class, $message, $details) = @_;
    return $class->new(ERROR_PERMISSION, $message, $details);
}

sub not_found_error {
    my ($class, $message, $details) = @_;
    return $class->new(ERROR_NOT_FOUND, $message, $details);
}

sub timeout_error {
    my ($class, $message, $details) = @_;
    return $class->new(ERROR_TIMEOUT, $message, $details);
}

1;
```

### 2. Gestionnaire d'Erreurs avec Retry

```perl
# Ajout dans S3/Client.pm

sub _execute_with_retry {
    my ($self, $operation, $max_retries, $backoff_factor) = @_;
    
    $max_retries //= 3;
    $backoff_factor //= 2;
    
    my $attempt = 0;
    my $delay = 1;
    
    while ($attempt <= $max_retries) {
        $attempt++;
        
        eval {
            return $operation->();
        };
        
        if (!$@) {
            return; # Succès
        }
        
        my $error = $@;
        PVE::Storage::S3::Utils::log_warn("Attempt $attempt failed: $error");
        
        # Analyse du type d'erreur pour décider si on retry
        if ($self->_should_retry($error) && $attempt <= $max_retries) {
            PVE::Storage::S3::Utils::log_info("Retrying in ${delay}s...");
            sleep($delay);
            $delay *= $backoff_factor;
        } else {
            die $error;
        }
    }
}

sub _should_retry {
    my ($self, $error) = @_;
    
    # Retry sur les erreurs temporaires
    return 1 if $error =~ /timeout/i;
    return 1 if $error =~ /connection/i;  
    return 1 if $error =~ /503|502|500/; # Erreurs serveur
    return 1 if $error =~ /ThrottlingException/;
    return 1 if $error =~ /RequestTimeout/;
    
    # Ne pas retry sur les erreurs permanentes
    return 0 if $error =~ /403|401/; # Auth errors
    return 0 if $error =~ /404/; # Not found
    return 0 if $error =~ /400/; # Bad request
    
    return 0; # Par défaut, ne pas retry
}
```

## Tests et Validation

### 1. Suite de Tests Unitaires

```perl
#!/usr/bin/perl
# test-s3-plugin.pl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile tempdir);
use JSON;

# Import du plugin
use lib '/usr/share/perl5';
use PVE::Storage::S3Plugin;
use PVE::Storage::S3::Client;
use PVE::Storage::S3::Config;
use PVE::Storage::S3::Auth;

plan tests => 25;

# Configuration de test
my $test_config = {
    endpoint => 'http://localhost:9000', # MinIO local
    region => 'us-east-1',
    bucket => 'test-bucket',
    prefix => 'test/',
    access_key => 'minioadmin',
    secret_key => 'minioadmin',
    multipart_chunk_size => 5 * 1024 * 1024, # 5MB
};

# Test 1: Création du plugin
{
    my $plugin = PVE::Storage::S3Plugin->new();
    isa_ok($plugin, 'PVE::Storage::S3Plugin', 'Plugin creation');
    is($plugin->type(), 's3', 'Plugin type');
}

# Test 2: Configuration
{
    my $properties = PVE::Storage::S3Plugin->properties();
    ok(exists $properties->{endpoint}, 'Endpoint property exists');
    ok(exists $properties->{bucket}, 'Bucket property exists');
    ok(exists $properties->{access_key}, 'Access key property exists');
}

# Test 3: Client S3
SKIP: {
    skip "MinIO not available", 5 unless test_minio_available();
    
    my $config = PVE::Storage::S3::Config->new($test_config);
    my $auth = PVE::Storage::S3::Auth->new({
        access_key => $test_config->{access_key},
        secret_key => $test_config->{secret_key},
    });
    
    my $client = PVE::Storage::S3::Client->new($config, $auth);
    isa_ok($client, 'PVE::Storage::S3::Client', 'S3 Client creation');
    
    lives_ok { $client->test_connection() } 'Connection test';
    
    # Test création bucket
    lives_ok { 
        eval { $client->head_bucket($test_config->{bucket}) };
        if ($@ && $@ =~ /NoSuchBucket/) {
            $client->create_bucket($test_config->{bucket});
        }
    } 'Bucket creation/verification';
    
    # Test upload fichier
    my ($fh, $filename) = tempfile();
    print $fh "Test content for S3 plugin\n" x 1000;
    close $fh;
    
    lives_ok {
        $client->upload_file($filename, $test_config->{bucket}, 'test/upload-test.txt');
    } 'File upload';
    
    # Test liste objets
    my $objects;
    lives_ok {
        $objects = $client->list_objects($test_config->{bucket}, 'test/');
    } 'List objects';
    
    is(scalar(@$objects), 1, 'Object count after upload');
    
    unlink $filename;
}

# Test 4: Gestion des erreurs
{
    my $bad_config = {%$test_config, access_key => 'invalid'};
    my $config = PVE::Storage::S3::Config->new($bad_config);
    my $auth = PVE::Storage::S3::Auth->new({
        access_key => 'invalid',
        secret_key => 'invalid',
    });
    
    my $client = PVE::Storage::S3::Client->new($config, $auth);
    
    throws_ok {
        $client->test_connection();
    } qr/Connection test failed/, 'Invalid credentials error';
}

# Test 5: Upload multipart
SKIP: {
    skip "MinIO not available", 3 unless test_minio_available();
    
    my $config = PVE::Storage::S3::Config->new($test_config);
    my $auth = PVE::Storage::S3::Auth->new({
        access_key => $test_config->{access_key},
        secret_key => $test_config->{secret_key},
    });
    
    my $client = PVE::Storage::S3::Client->new($config, $auth);
    
    # Création d'un fichier de 10MB
    my ($fh, $filename) = tempfile();
    my $chunk = "A" x 1024; # 1KB
    for (1..10240) { # 10MB total
        print $fh $chunk;
    }
    close $fh;
    
    lives_ok {
        $client->upload_file($filename, $test_config->{bucket}, 'test/multipart-test.txt');
    } 'Multipart upload';
    
    # Vérification de l'upload
    my $objects = $client->list_objects($test_config->{bucket}, 'test/multipart-test.txt');
    is(scalar(@$objects), 1, 'Multipart object uploaded');
    is($objects->[0]->{Size}, 10 * 1024 * 1024, 'Multipart object size');
    
    unlink $filename;
}

# Test 6: Path generation
{
    my $scfg = {
        bucket => 'test-bucket',
        prefix => 'proxmox/',
    };
    
    my ($bucket, $path) = PVE::Storage::S3Plugin->path($scfg, 'vm-100-disk-1.qcow2', 'storage1');
    is($bucket, 'test-bucket', 'Bucket path generation');
    is($path, 'proxmox/vm-100-disk-1.qcow2', 'Object path generation');
    
    # Test avec snapshot
    ($bucket, $path) = PVE::Storage::S3Plugin->path($scfg, 'vm-100-disk-1.qcow2', 'storage1', 'snap1');
    is($path, 'proxmox/snapshots/vm-100-disk-1.qcow2/snap1', 'Snapshot path generation');
}

# Test 7: Plugin data
{
    my $data = PVE::Storage::S3Plugin->plugindata();
    ok(exists $data->{content}, 'Plugin data has content');
    ok(exists $data->{format}, 'Plugin data has format');
    
    my $content_types = $data->{content};
    my $has_backup = grep { exists $_->{backup} } @$content_types;
    ok($has_backup, 'Backup content type supported');
}

# Fonction utilitaire pour tester MinIO
sub test_minio_available {
    my $ua = LWP::UserAgent->new(timeout => 5);
    my $response = eval { $ua->head('http://localhost:9000') };
    return $response && $response->is_success;
}

done_testing();

print "\n=== Test Summary ===\n";
print "S3 Plugin tests completed.\n";
print "Run with MinIO server on localhost:9000 for complete testing.\n";
```

### 2. Tests d'Intégration

```bash
#!/bin/bash
# integration-tests.sh

set -e

STORAGE_ID="test-s3"
TEST_VM_ID="999"
LOG_FILE="/tmp/s3-integration-test.log"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

log "Starting S3 Plugin Integration Tests"

# Vérification de l'installation du plugin
log "Testing plugin installation..."
if ! pvesm help | grep -q "s3"; then
    log "ERROR: S3 plugin not installed"
    exit 1
fi

# Configuration temporaire du storage
log "Configuring test storage..."
cat >> /etc/pve/storage.cfg << EOF

$STORAGE_ID: $STORAGE_ID
    endpoint http://localhost:9000
    region us-east-1
    bucket proxmox-test
    access_key minioadmin
    secret_key minioadmin
    prefix test/
    content backup,iso,vztmpl
    maxfiles 5
EOF

# Test activation du storage
log "Testing storage activation..."
if pvesm status "$STORAGE_ID" >/dev/null 2>&1; then
    log "✓ Storage activation successful"
else
    log "✗ Storage activation failed"
    exit 1
fi

# Test de connectivité
log "Testing S3 connectivity..."
if pvesm list "$STORAGE_ID" >/dev/null 2>&1; then
    log "✓ S3 connectivity successful"  
else
    log "✗ S3 connectivity failed"
    exit 1
fi

# Test upload d'un fichier ISO
log "Testing ISO upload..."
ISO_FILE="/tmp/test.iso"
dd if=/dev/zero of="$ISO_FILE" bs=1M count=10 2>/dev/null

if pvesm upload "$STORAGE_ID" "$ISO_FILE" "test.iso"; then
    log "✓ ISO upload successful"
    rm "$ISO_FILE"
else
    log "✗ ISO upload failed"
    rm -f "$ISO_FILE"
    exit 1
fi

# Vérification de la liste des fichiers
log "Testing file listing..."
if pvesm list "$STORAGE_ID" | grep -q "test.iso"; then
    log "✓ File listing successful"
else
    log "✗ File not found in listing"
fi

# Test de backup (si VM de test existe)
if qm status "$TEST_VM_ID" >/dev/null 2>&1; then
    log "Testing VM backup..."
    if vzdump "$TEST_VM_ID" --storage "$STORAGE_ID" --mode snapshot --compress gzip; then
        log "✓ VM backup successful"
    else
        log "✗ VM backup failed"
    fi
fi

# Nettoyage 
log "Cleaning up..."
pvesm free "$STORAGE_ID:iso/test.iso" 2>/dev/null || true

# Suppression de la configuration de test
sed -i "/^$STORAGE_ID:/,/^$/d" /etc/pve/storage.cfg

log "Integration tests completed successfully"
```

## Optimisations et Performance

### 1. Pool de Connexions

```perl
# Ajout dans S3/Client.pm

package PVE::Storage::S3::ConnectionPool;

use strict;
use warnings;

my %connection_pool;
my $max_pool_size = 10;
my $connection_timeout = 300; # 5 minutes

sub get_connection {
    my ($class, $endpoint) = @_;
    
    # Nettoyage des connexions expirées
    $class->_cleanup_expired_connections();
    
    my $pool = $connection_pool{$endpoint} //= [];
    
    # Récupère une connexion disponible
    if (@$pool > 0) {
        my $conn = pop @$pool;
        if ($conn->{expires_at} > time()) {
            return $conn->{ua};
        }
    }
    
    # Crée une nouvelle connexion
    my $ua = LWP::UserAgent->new(
        timeout => 60,
        keep_alive => 10,
        agent => 'Proxmox-S3-Plugin/1.0',
    );
    
    return $ua;
}

sub return_connection {
    my ($class, $endpoint, $ua) = @_;
    
    my $pool = $connection_pool{$endpoint} //= [];
    
    return if @$pool >= $max_pool_size;
    
    push @$pool, {
        ua => $ua,
        expires_at => time() + $connection_timeout,
    };
}

sub _cleanup_expired_connections {
    my ($class) = @_;
    
    my $now = time();
    foreach my $endpoint (keys %connection_pool) {
        my $pool = $connection_pool{$endpoint};
        @$pool = grep { $_->{expires_at} > $now } @$pool;
        delete $connection_pool{$endpoint} if @$pool == 0;
    }
}

1;
```

### 2. Cache des Métadonnées

```perl
package PVE::Storage::S3::MetadataCache;

use strict;
use warnings;
use JSON;
use File::Path qw(make_path);
use Fcntl qw(:flock);

my $cache_dir = '/var/cache/pve/s3-metadata';
my $cache_ttl = 300; # 5 minutes

sub new {
    my ($class, $storage_id) = @_;
    
    my $self = {
        storage_id => $storage_id,
        cache_file => "$cache_dir/$storage_id.json",
    };
    
    make_path($cache_dir) unless -d $cache_dir;
    
    return bless $self, $class;
}

sub get {
    my ($self, $key) = @_;
    
    my $cache = $self->_load_cache();
    my $entry = $cache->{$key};
    
    return undef unless $entry;
    return undef if $entry->{expires_at} < time();
    
    return $entry->{data};
}

sub set {
    my ($self, $key, $data, $ttl) = @_;
    
    $ttl //= $cache_ttl;
    
    my $cache = $self->_load_cache();
    $cache->{$key} = {
        data => $data,
        expires_at => time() + $ttl,
    };
    
    $self->_save_cache($cache);
}

sub invalidate {
    my ($self, $key) = @_;
    
    my $cache = $self->_load_cache();
    delete $cache->{$key};
    $self->_save_cache($cache);
}

sub clear {
    my ($self) = @_;
    
    unlink $self->{cache_file};
}

sub _load_cache {
    my ($self) = @_;
    
    return {} unless -f $self->{cache_file};
    
    open my $fh, '<', $self->{cache_file} or return {};
    flock($fh, LOCK_SH) or return {};
    
    my $content = do { local $/; <$fh> };
    close $fh;
    
    return {} unless $content;
    
    my $cache = eval { decode_json($content) };
    return {} if $@;
    
    # Nettoyage des entrées expirées
    my $now = time();
    foreach my $key (keys %$cache) {
        delete $cache->{$key} if $cache->{$key}->{expires_at} < $now;
    }
    
    return $cache;
}

sub _save_cache {
    my ($self, $cache) = @_;
    
    my $json = encode_json($cache);
    
    open my $fh, '>', $self->{cache_file} or die "Cannot write cache: $!";
    flock($fh, LOCK_EX) or die "Cannot lock cache: $!";
    
    print $fh $json;
    close $fh;
}

1;
```

## Exemples d'Utilisation

### 1. Script de Backup Automatisé

```bash
#!/bin/bash
# pve-s3-intelligent-backup.sh

set -e

STORAGE_ID="${1:-s3-backup}"
CONFIG_FILE="/etc/pve/s3-backup.conf"
LOG_FILE="/var/log/pve/s3-backup.log"

# Configuration par défaut
DEFAULT_RETENTION_DAILY=7
DEFAULT_RETENTION_WEEKLY=4
DEFAULT_RETENTION_MONTHLY=12
DEFAULT_COMPRESSION="gzip"
DEFAULT_MODE="snapshot"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    exit 1
}

# Chargement de la configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    log "Using default configuration"
fi

RETENTION_DAILY=${RETENTION_DAILY:-$DEFAULT_RETENTION_DAILY}
RETENTION_WEEKLY=${RETENTION_WEEKLY:-$DEFAULT_RETENTION_WEEKLY}  
RETENTION_MONTHLY=${RETENTION_MONTHLY:-$DEFAULT_RETENTION_MONTHLY}
COMPRESSION=${COMPRESSION:-$DEFAULT_COMPRESSION}
MODE=${MODE:-$DEFAULT_MODE}

log "Starting intelligent S3 backup"

# Vérification du storage
if ! pvesm status "$STORAGE_ID" >/dev/null 2>&1; then
    error "Storage $STORAGE_ID not available"
fi

# Liste des VMs à sauvegarder
VM_LIST=$(qm list | tail -n +2 | awk '{print $1}')
CT_LIST=$(pct list | tail -n +2 | awk '{print $1}')

backup_vm() {
    local vmid=$1
    local vm_name=$(qm config "$vmid" | grep '^name:' | cut -d' ' -f2)
    vm_name=${vm_name:-"vm-$vmid"}
    
    log "Backing up VM $vmid ($vm_name)"
    
    # Vérification de l'état de la VM
    local vm_status=$(qm status "$vmid" | awk '{print $2}')
    
    if [ "$vm_status" != "running" ] && [ "$MODE" = "snapshot" ]; then
        log "VM $vmid not running, using suspend mode"
        local backup_mode="suspend"
    else
        local backup_mode="$MODE"
    fi
    
    # Génération du nom de fichier
    local timestamp=$(date '+%Y_%m_%d-%H_%M_%S')
    local backup_filename="vzdump-qemu-${vmid}-${timestamp}.vma"
    
    if [ "$COMPRESSION" != "none" ]; then
        backup_filename="${backup_filename}.${COMPRESSION}"
    fi
    
    # Exécution du backup
    if vzdump "$vmid" \
        --storage "$STORAGE_ID" \
        --mode "$backup_mode" \
        --compress "$COMPRESSION" \
        --mailto admin@example.com \
        --mailnotification failure; then
        log "✓ VM $vmid backup completed: $backup_filename"
    else
        log "✗ VM $vmid backup failed"
        return 1
    fi
}

backup_container() {
    local ctid=$1
    local ct_name=$(pct config "$ctid" | grep '^hostname:' | cut -d' ' -f2)
    ct_name=${ct_name:-"ct-$ctid"}
    
    log "Backing up Container $ctid ($ct_name)"
    
    local timestamp=$(date '+%Y_%m_%d-%H_%M_%S')
    local backup_filename="vzdump-lxc-${ctid}-${timestamp}.tar"
    
    if [ "$COMPRESSION" != "none" ]; then
        backup_filename="${backup_filename}.${COMPRESSION}"
    fi
    
    if vzdump "$ctid" \
        --storage "$STORAGE_ID" \
        --mode "$MODE" \
        --compress "$COMPRESSION" \
        --mailto admin@example.com \
        --mailnotification failure; then
        log "✓ Container $ctid backup completed: $backup_filename"
    else
        log "✗ Container $ctid backup failed"
        return 1
    fi
}

cleanup_old_backups() {
    log "Cleaning up old backups"
    
    local backups=$(pvesm list "$STORAGE_ID" | grep backup | awk '{print $1}')
    
    # Logique de rétention basée sur la date
    local now=$(date +%s)
    local day_seconds=86400
    local week_seconds=$((day_seconds * 7))
    local month_seconds=$((day_seconds * 30))
    
    echo "$backups" | while read backup_volid; do
        if [ -z "$backup_volid" ]; then continue; fi
        
        # Extraction de la date depuis le nom du fichier
        local backup_name=$(basename "$backup_volid")
        if [[ $backup_name =~ ([0-9]{4}_[0-9]{2}_[0-9]{2})-([0-9]{2}_[0-9]{2}_[0-9]{2}) ]]; then
            local backup_date="${BASH_REMATCH[1]}"
            local backup_time="${BASH_REMATCH[2]}"
            
            # Conversion en timestamp
            local backup_timestamp=$(date -d "${backup_date//_/-} ${backup_time//_/:}" +%s 2>/dev/null || echo 0)
            
            if [ "$backup_timestamp" -gt 0 ]; then
                local age_seconds=$((now - backup_timestamp))
                local age_days=$((age_seconds / day_seconds))
                
                local should_delete=0
                
                # Règles de rétention
                if [ $age_days -gt $RETENTION_DAILY ] && [ $age_days -le $((RETENTION_WEEKLY * 7)) ]; then
                    # Zone hebdomadaire - garde seulement les sauvegardes du dimanche
                    local backup_weekday=$(date -d "${backup_date//_/-}" +%w)
                    [ "$backup_weekday" -ne 0 ] && should_delete=1
                elif [ $age_days -gt $((RETENTION_WEEKLY * 7)) ] && [ $age_days -le $((RETENTION_MONTHLY * 30)) ]; then
                    # Zone mensuelle - garde seulement les sauvegardes du 1er du mois
                    local backup_day=$(date -d "${backup_date//_/-}" +%d)
                    [ "$backup_day" -ne 1 ] && should_delete=1
                elif [ $age_days -gt $((RETENTION_MONTHLY * 30)) ]; then
                    # Plus ancien que la rétention mensuelle
                    should_delete=1
                fi
                
                if [ $should_delete -eq 1 ]; then
                    log "Deleting old backup: $backup_name (${age_days} days old)"
                    pvesm free "$backup_volid" 2>/dev/null || log "Warning: Could not delete $backup_volid"
                fi
            fi
        fi
    done
}

# Exécution des backups
failed_backups=0

# Backup des VMs
for vmid in $VM_LIST; do
    if ! backup_vm "$vmid"; then
        ((failed_backups++))
    fi
done

# Backup des containers
for ctid in $CT_LIST; do
    if ! backup_container "$ctid"; then
        ((failed_backups++))
    fi
done

# Nettoyage
cleanup_old_backups

# Rapport final
total_vms=$(echo "$VM_LIST" | wc -w)
total_cts=$(echo "$CT_LIST" | wc -w)
total_backups=$((total_vms + total_cts))
successful_backups=$((total_backups - failed_backups))

log "Backup completed: $successful_backups/$total_backups successful"

if [ $failed_backups -gt 0 ]; then
    error "Some backups failed ($