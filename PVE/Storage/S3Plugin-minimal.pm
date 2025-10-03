package PVE::Storage::S3Plugin;

use strict;
use warnings;
use base qw(PVE::Storage::Plugin);

# Configuration du type de plugin
sub type {
    return 's3';
}

sub plugindata {
    return {
	content => [ { backup => 1, iso => 1, vztmpl => 1, snippets => 1 } ],
	format => [ { raw => 1, qcow2 => 1, vmdk => 1 } ],
    };
}

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
	    optional => 1,
	},
	secret_key => {
	    description => "S3 Secret Key", 
	    type => 'string',
	    optional => 1,
	},
	prefix => {
	    description => "S3 Key prefix",
	    type => 'string',
	    optional => 1,
	    default => '',
	},
    };
}

sub options {
    return {
	bucket => { fixed => 1 },
	endpoint => { fixed => 1 },
	region => { optional => 1 },
	access_key => { optional => 1 },
	secret_key => { optional => 1, password => 1 },
	prefix => { optional => 1 },
	content => { optional => 1 },
	nodes => { optional => 1 },
	disable => { optional => 1 },
	maxfiles => { optional => 1 },
	shared => { optional => 1 },
    };
}

# Méthodes minimales requises
sub on_add_hook {
    my ($class, $storeid, $scfg, %param) = @_;
    return undef;
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    # Retourner des valeurs par défaut : total, available, used, active
    return (1000000000000, 500000000000, 500000000000, 1);
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    return 1;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    return 1;
}

sub list_images {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    return [];
}

sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;
    my $bucket = $scfg->{bucket};
    my $prefix = $scfg->{prefix} || '';
    return "s3://$bucket/$prefix$volname";
}

sub create_base {
    my ($class, $storeid, $scfg, $volname) = @_;
    die "create base image not supported for S3 storage\n";
}

sub clone_image {
    my ($class, $scfg, $storeid, $volname, $vmid, $snapname) = @_;
    die "clone image not supported for S3 storage\n";
}

sub alloc_image {
    my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;
    die "alloc image not supported for S3 storage\n";
}

sub free_image {
    my ($class, $storeid, $scfg, $volname, $isBase) = @_;
    return undef;
}

# Enregistrement du plugin - CRITIQUE !
PVE::Storage::Plugin::register_storage_type('s3', __PACKAGE__);

1;