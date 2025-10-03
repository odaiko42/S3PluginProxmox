package PVE::Storage::Custom::S3Plugin;

use strict;
use warnings;

use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use PVE::Tools;
use PVE::Storage::Custom::S3Client;
use File::Path;
use File::Basename;
use File::Temp qw(tempfile);

use base qw(PVE::Storage::Plugin);

# Version API supportée
sub api {
    return 12;
}

# Type de stockage
sub type {
    return 's3';
}

# Métadonnées du plugin
sub plugindata {
    return {
        content => [ 
            { images => 1, format => 'raw' },
            { images => 1, format => 'qcow2' }, 
            { images => 1, format => 'vmdk' },
            { backup => 1, format => 'vma' },
            { backup => 1, format => 'tar' },
            { backup => 1, format => 'tgz' },
            { vztmpl => 1, format => 'tar.gz' },
            { vztmpl => 1, format => 'tar.xz' },
            { iso => 1, format => 'iso' },
        ],
        format => [ 
            { raw => 1 },
            { qcow2 => 1 },
            { vmdk => 1 },
            { vma => 1 },
            { tar => 1 },
            { tgz => 1 },
            { iso => 1 },
        ],
        select_existing => 0,
        clone => 0,
        shared => 1,
    };
}

# Propriétés du plugin
sub properties {
    return {
        bucket => {
            description => "S3 Bucket name",
            type => 'string',
        },
        endpoint => {
            description => "S3 Endpoint URL", 
            type => 'string',
        },
        region => {
            description => "S3 Region",
            type => 'string',
            optional => 1,
            default => 'us-east-1',
        },
        access_key => {
            description => "S3 Access Key",
            type => 'string',
        },
        secret_key => {
            description => "S3 Secret Key",
            type => 'string',
        },
        prefix => {
            description => "Object prefix (optional)",
            type => 'string',
            optional => 1,
        },
    };
}

# Options configurables
sub options {
    return {
        bucket => { fixed => 1 },
        endpoint => { fixed => 1 },
        region => { optional => 1 },
        access_key => { fixed => 1 },
        secret_key => { fixed => 1 },
        prefix => { optional => 1 },
        content => { optional => 1 },
        format => { optional => 1 },
        nodes => { optional => 1 },
        disable => { optional => 1 },
        maxfiles => { optional => 1 },
    };
}

# Créer le client S3
sub _get_s3_client {
    my ($class, $scfg) = @_;
    
    return PVE::Storage::Custom::S3Client->new(
        endpoint => $scfg->{endpoint},
        region => $scfg->{region} || 'us-east-1',
        access_key => $scfg->{access_key},
        secret_key => $scfg->{secret_key},
        bucket => $scfg->{bucket},
        prefix => $scfg->{prefix} || '',
    );
}

# Test de connectivité
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    my ($success, $msg) = $s3->test_connection();
    
    if (!$success) {
        die "S3 storage '$storeid' is not available: $msg";
    }
    
    return ($success * 1024*1024*1024, 512*1024*1024, $success * 1024*1024*1024 - 100*1024*1024, 1);
}

# Générer le nom de fichier pour un volume
sub _get_volume_filename {
    my ($class, $volname, $format) = @_;
    
    my $filename = $volname;
    
    if ($format eq 'raw') {
        $filename .= '.raw';
    } elsif ($format eq 'qcow2') {
        $filename .= '.qcow2';
    } elsif ($format eq 'vmdk') {
        $filename .= '.vmdk';
    } elsif ($format eq 'vma') {
        $filename .= '.vma';
    } elsif ($format eq 'tar') {
        $filename .= '.tar';
    } elsif ($format eq 'tgz') {
        $filename .= '.tgz';
    } elsif ($format eq 'tar.gz') {
        $filename .= '.tar.gz';
    } elsif ($format eq 'tar.xz') {
        $filename .= '.tar.xz';
    } elsif ($format eq 'iso') {
        $filename .= '.iso';
    }
    
    return $filename;
}

# Parser le nom de volume
sub parse_name {
    my ($class, $volname) = @_;
    
    if ($volname =~ m/^(backup-\d+-\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2})\.(vma|tar|tgz)$/) {
        return ('backup', $1, undef, undef, undef, undef, $2);
    } elsif ($volname =~ m/^(vm-(\d+)-\w+)\.(raw|qcow2|vmdk)$/) {
        return ('images', $1, $2, undef, undef, undef, $3);
    } elsif ($volname =~ m/^(ct-(\d+)-\w+)\.(tar\.gz|tar\.xz)$/) {
        return ('rootdir', $1, $2, undef, undef, undef, $3);
    } elsif ($volname =~ m/^([^\/]+\.(iso|tar\.gz|tar\.xz))$/) {
        my $name = $1;
        my $format = $2;
        if ($format eq 'iso') {
            return ('iso', $name, undef, undef, undef, undef, $format);
        } else {
            return ('vztmpl', $name, undef, undef, undef, undef, $format);
        }
    }
    
    return undef;
}

# Lister les volumes/images
sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    my $res = [];
    
    eval {
        my $objects = $s3->list_objects();
        
        foreach my $obj (@$objects) {
            my $key = $obj->{key};
            
            # Parser le nom du fichier
            my ($vtype, $name, $parsed_vmid, $base_name, $base_vmid, $isBase, $format) = 
                $class->parse_name($key);
                
            next if !defined($vtype);
            next if $vmid && $parsed_vmid && $parsed_vmid != $vmid;
            
            my $volid = "$storeid:$key";
            
            my $info = {
                volid => $volid,
                size => $obj->{size},
                format => $format,
                vmid => $parsed_vmid,
                content => $vtype,
                ctime => $obj->{modified} ? PVE::Tools::datetime_to_epoch($obj->{modified}) : time(),
            };
            
            push @$res, $info;
        }
    };
    
    if ($@) {
        warn "Error listing S3 objects: $@";
    }
    
    return $res;
}

# Obtenir les informations d'un volume
sub volume_size_info {
    my ($class, $scfg, $storeid, $volname) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    my $info = $s3->head_object($volname);
    
    return $info ? $info->{size} : 0;
}

# Créer un nouveau volume 
sub alloc_image {
    my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;
    
    die "S3 storage does not support creating new volumes directly\n";
}

# Vérifier si un volume existe
sub volume_has_feature {
    my ($class, $scfg, $feature, $storeid, $volname, $snapname, $running, $opts) = @_;
    
    my $features = {
        copy => { current => 1 },
        sparseinit => { base => 1, current => 1 },
    };
    
    my ($vtype, $name, $vmid, $basename, $basevmid, $isBase) = $class->parse_name($volname);
    
    my $key = $snapname ? 'snap' : $isBase ? 'base' : 'current';
    
    return 1 if $features->{$feature}->{$key};
    
    return undef;
}

# Copier/télécharger un fichier depuis S3
sub file_read {
    my ($class, $scfg, $storeid, $filename) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    # Créer un fichier temporaire
    my ($fh, $tmpfile) = tempfile(UNLINK => 1);
    close $fh;
    
    # Télécharger depuis S3
    my $size = $s3->get_object($filename, $tmpfile);
    
    return $tmpfile;
}

# Upload/copier un fichier vers S3
sub file_write {
    my ($class, $scfg, $storeid, $filename, $data) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    # Créer un fichier temporaire pour les données
    my ($fh, $tmpfile) = tempfile(UNLINK => 1);
    print $fh $data;
    close $fh;
    
    # Upload vers S3
    my $etag = $s3->put_object($filename, $tmpfile);
    
    unlink $tmpfile;
    
    return length($data);
}

# Supprimer un volume
sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase, $format) = @_;
    
    my $s3 = $class->_get_s3_client($scfg);
    
    $s3->delete_object($volname);
    
    return undef;
}

# Obtenir le chemin d'activation
sub activate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;
    
    # Les volumes S3 ne peuvent pas être montés directement
    return undef;
}

# Désactiver un volume
sub deactivate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;
    
    # Rien à faire pour S3
    return undef;
}

# Obtenir le chemin du volume
sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;
    
    # Retourner un chemin virtuel pour S3
    return ("s3://" . $scfg->{bucket} . "/" . ($scfg->{prefix} || '') . $volname, $volname, 'raw');
}

1;