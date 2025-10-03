
package PVE::Storage::S3Plugin;

use strict;
use warnings;

use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use PVE::Tools;

use base qw(PVE::Storage::Plugin);
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
    
    return 1;
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