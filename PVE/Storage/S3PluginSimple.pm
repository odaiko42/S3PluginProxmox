package PVE::Storage::S3Plugin;

use strict;
use warnings;

use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);
use PVE::Tools;

use base qw(PVE::Storage::Plugin);

# Constructeur
sub new {
    my ($class) = @_;
    return bless {}, $class;
}

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
        content => [ { backup => 1, iso => 1, vztmpl => 1, snippets => 1 } ],
        format => [ { raw => 1, qcow2 => 1, vmdk => 1 } ],
        select_existing => 0,
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
        content => { optional => 1 },
        nodes => { optional => 1 },
        disable => { optional => 1 },
        maxfiles => { optional => 1 },
    };
}

# Test de connectivité
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    return (1024*1024*1024, 512*1024*1024, 512*1024*1024, 1);
}

# Chemin du volume
sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;
    return ("s3://$scfg->{bucket}/$volname", $volname, 'raw');
}

# Liste des images
sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    return [];
}

# Activation volume
sub activate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;
    return undef;
}

# Désactivation volume
sub deactivate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;
    return undef;
}

1;