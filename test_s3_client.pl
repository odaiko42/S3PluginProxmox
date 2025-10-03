#!/usr/bin/perl

use strict;
use warnings;

use lib '/usr/share/perl5';
use lib '.';

use PVE::Storage::Custom::S3Client;
use Data::Dumper;

# Configuration de test
my $config = {
    endpoint => 'localhost:9000',  # MinIO local
    region => 'us-east-1',
    access_key => 'minioadmin',
    secret_key => 'minioadmin',
    bucket => 'test-bucket',
    prefix => 'proxmox/',
};

print "=== Test du client S3 ===\n";

# Créer le client
my $s3 = eval {
    PVE::Storage::Custom::S3Client->new(%$config);
};

if ($@) {
    print "Erreur création client: $@\n";
    exit 1;
}

print "Client S3 créé avec succès\n";

# Test de connexion
print "\nTest de connexion...\n";
my ($success, $msg) = $s3->test_connection();

if ($success) {
    print "✓ Connexion S3 réussie: $msg\n";
} else {
    print "✗ Échec connexion S3: $msg\n";
    exit 1;
}

# Test listing des objets
print "\nListe des objets dans le bucket...\n";
my $objects = eval { $s3->list_objects(); };

if ($@) {
    print "Erreur listing: $@\n";
} else {
    print "Nombre d'objets trouvés: " . scalar(@$objects) . "\n";
    
    foreach my $obj (@$objects) {
        print "  - $obj->{key} ($obj->{size} bytes, $obj->{modified})\n";
    }
}

# Test upload d'un fichier de test
print "\nCréation et upload d'un fichier de test...\n";

my $test_file = "/tmp/s3-test-file.txt";
my $test_content = "Test file for S3 plugin - " . localtime() . "\n";

# Créer le fichier de test
open my $fh, '>', $test_file or die "Cannot create test file: $!";
print $fh $test_content;
close $fh;

# Upload
my $test_key = "test/uploaded-file.txt";
my $etag = eval { $s3->put_object($test_key, $test_file); };

if ($@) {
    print "Erreur upload: $@\n";
} else {
    print "✓ Upload réussi, ETag: $etag\n";
}

# Test head object
print "\nVérification des métadonnées de l'objet...\n";
my $head_info = eval { $s3->head_object($test_key); };

if ($@) {
    print "Erreur head: $@\n";
} elsif ($head_info) {
    print "✓ Objet trouvé:\n";
    print "  - Taille: $head_info->{size} bytes\n";
    print "  - Modifié: $head_info->{modified}\n";
    print "  - ETag: $head_info->{etag}\n";
} else {
    print "✗ Objet non trouvé\n";
}

# Test download
print "\nTéléchargement du fichier...\n";
my $download_file = "/tmp/s3-downloaded-file.txt";
my $download_size = eval { $s3->get_object($test_key, $download_file); };

if ($@) {
    print "Erreur download: $@\n";
} else {
    print "✓ Download réussi, $download_size bytes\n";
    
    # Vérifier le contenu
    open my $dfh, '<', $download_file or die "Cannot read downloaded file: $!";
    my $downloaded_content = do { local $/; <$dfh> };
    close $dfh;
    
    if ($downloaded_content eq $test_content) {
        print "✓ Contenu vérifié - identique à l'original\n";
    } else {
        print "✗ Contenu différent!\n";
        print "  Original: $test_content";
        print "  Téléchargé: $downloaded_content";
    }
}

# Test suppression
print "\nSuppression du fichier de test...\n";
my $delete_ok = eval { $s3->delete_object($test_key); };

if ($@) {
    print "Erreur suppression: $@\n";
} else {
    print "✓ Suppression réussie\n";
}

# Nettoyage
unlink $test_file if -f $test_file;
unlink $download_file if -f $download_file;

print "\n=== Tests terminés ===\n";