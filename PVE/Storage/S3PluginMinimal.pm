package PVE::Storage::S3Plugin;

use strict;
use warnings;

use PVE::Storage::DirPlugin;
use PVE::JSONSchema qw(get_standard_option);

use base qw(PVE::Storage::DirPlugin);

# Type de stockage
sub type {
    return 's3';
}

# Métadonnées du plugin
sub plugindata {
    return {
        content => [{ backup => 1, iso => 1, vztmpl => 1 }],
        format => [{ raw => 1, qcow2 => 1, vmdk => 1 }, 'raw'],
    };
}

# Propriétés spécifiques S3
sub properties {
    return {
        %{PVE::Storage::DirPlugin->properties()},
        bucket => {
            description => "S3 Bucket name",
            type => 'string',
        },
        endpoint => {
            description => "S3 Endpoint URL",
            type => 'string',
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
        %{PVE::Storage::DirPlugin->options()},
        bucket => { fixed => 1 },
        endpoint => { fixed => 1 },
        access_key => { fixed => 1 },
        secret_key => { fixed => 1 },
    };
}

# Méthode register OBLIGATOIRE
sub register {
    my ($class) = @_;
    # Enregistrement minimal
    return;
}

# Test de connexion S3 simplifié
sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    # Test basique : vérifier que les paramètres S3 sont présents
    return undef if !$scfg->{bucket} || !$scfg->{endpoint};
    
    # Déléguer au parent (DirPlugin)
    return $class->SUPER::status($storeid, $scfg, $cache);
}

1;