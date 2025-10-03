#!/usr/bin/perl

use strict;
use warnings;

use lib '/usr/share/perl5';
use lib '.';

use PVE::Storage::Custom::S3PluginFull;
use Data::Dumper;

print "=== Test du plugin S3 complet ===\n";

# Configuration de test
my $scfg = {
    type => 's3',
    storage => 'test-s3',
    bucket => 'test-bucket',
    endpoint => 'localhost:9000',
    region => 'us-east-1',
    access_key => 'minioadmin',
    secret_key => 'minioadmin',
    prefix => 'proxmox/',
    content => { backup => 1, images => 1, iso => 1 },
};

my $storeid = 'test-s3';

print "Configuration du stockage:\n";
print Dumper($scfg);

# Test des méthodes du plugin
print "\nTest de la méthode type()...\n";
my $type = PVE::Storage::Custom::S3PluginFull->type();
print "Type: $type\n";

print "\nTest de la méthode api()...\n";
my $api = PVE::Storage::Custom::S3PluginFull->api();
print "API version: $api\n";

print "\nTest de la méthode plugindata()...\n";
my $plugindata = PVE::Storage::Custom::S3PluginFull->plugindata();
print "Plugin data:\n";
print Dumper($plugindata);

print "\nTest de la méthode properties()...\n";
my $properties = PVE::Storage::Custom::S3PluginFull->properties();
print "Properties:\n";
foreach my $prop (sort keys %$properties) {
    print "  $prop: $properties->{$prop}->{description}\n";
}

print "\nTest de la méthode options()...\n";
my $options = PVE::Storage::Custom::S3PluginFull->options();
print "Options:\n";
foreach my $opt (sort keys %$options) {
    my $req = $options->{$opt}->{fixed} ? "required" : "optional";
    print "  $opt: $req\n";
}

# Test du status (connexion S3)
print "\nTest de connexion S3 (status)...\n";
my ($total, $avail, $used, $active) = eval {
    PVE::Storage::Custom::S3PluginFull->status($storeid, $scfg);
};

if ($@) {
    print "Erreur status: $@\n";
} else {
    print "✓ Status OK:\n";
    print "  - Total: " . sprintf("%.2f GB", $total / (1024**3)) . "\n";
    print "  - Disponible: " . sprintf("%.2f GB", $avail / (1024**3)) . "\n";
    print "  - Utilisé: " . sprintf("%.2f GB", $used / (1024**3)) . "\n";
    print "  - Actif: " . ($active ? "Oui" : "Non") . "\n";
}

# Test du listing d'images
print "\nTest du listing des images...\n";
my $images = eval {
    PVE::Storage::Custom::S3PluginFull->list_images($storeid, $scfg);
};

if ($@) {
    print "Erreur list_images: $@\n";
} else {
    print "✓ Listing réussi, " . scalar(@$images) . " images trouvées:\n";
    
    foreach my $img (@$images) {
        print "  - $img->{volid} ($img->{format}, " . 
              sprintf("%.2f MB", $img->{size} / (1024**2)) . ")\n";
    }
}

# Test de parsing de noms
print "\nTest de parsing de noms de volumes...\n";

my @test_names = (
    'backup-100-2024_01_15-10_30_00.vma',
    'vm-100-disk-0.qcow2', 
    'vm-200-disk-1.raw',
    'ct-150-rootfs.tar.gz',
    'ubuntu-22.04.iso',
    'template-ubuntu.tar.gz',
);

foreach my $name (@$test_names) {
    my ($vtype, $volname, $vmid, $basename, $basevmid, $isBase, $format) = 
        PVE::Storage::Custom::S3PluginFull->parse_name($name);
        
    if ($vtype) {
        print "  ✓ $name -> Type: $vtype, Format: $format, VMID: " . ($vmid || 'N/A') . "\n";
    } else {
        print "  ✗ $name -> Non reconnu\n";
    }
}

# Test de génération de chemin
print "\nTest de génération de chemins...\n";
my $test_volname = 'vm-100-disk-0.qcow2';
my ($path, $ownervm, $vtype_path) = eval {
    PVE::Storage::Custom::S3PluginFull->path($scfg, $test_volname, $storeid);
};

if ($@) {
    print "Erreur path: $@\n";
} else {
    print "✓ Chemin pour $test_volname:\n";
    print "  - Path: $path\n";
    print "  - Owner VM: $ownervm\n";
    print "  - Type: $vtype_path\n";
}

print "\n=== Tests terminés ===\n";