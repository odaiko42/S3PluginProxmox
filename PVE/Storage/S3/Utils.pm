package PVE::Storage::S3::Utils;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(
    log_info log_warn log_error 
    parse_s3_time format_bytes 
    validate_bucket_name validate_key_name
    parse_endpoint sanitize_metadata
);

use POSIX qw(strftime);
use Time::Local;

# Configuration du logging
my $LOG_FILE = '/var/log/pve/storage-s3.log';
my $LOG_LEVEL = $ENV{PVE_S3_LOG_LEVEL} || 'INFO';

# Fonctions de logging
sub log_info {
    my ($message) = @_;
    _write_log('INFO', $message);
}

sub log_warn {
    my ($message) = @_;
    _write_log('WARN', $message);
}

sub log_error {
    my ($message) = @_;
    _write_log('ERROR', $message);
}

sub _write_log {
    my ($level, $message) = @_;
    
    return if !_should_log($level);
    
    my $timestamp = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $pid = $$;
    my $log_entry = "[$timestamp] [$level] [$$] $message\n";
    
    if (open my $fh, '>>', $LOG_FILE) {
        print $fh $log_entry;
        close $fh;
    } else {
        # Fallback vers syslog
        warn $log_entry;
    }
}

sub _should_log {
    my ($level) = @_;
    
    my %levels = (
        'DEBUG' => 0,
        'INFO'  => 1,
        'WARN'  => 2,
        'ERROR' => 3,
    );
    
    return ($levels{$level} // 1) >= ($levels{$LOG_LEVEL} // 1);
}

# Parse d'un timestamp S3 vers epoch Unix
sub parse_s3_time {
    my ($s3_time) = @_;
    
    return 0 if !$s3_time;
    
    # Format S3: 2023-12-25T14:30:00.000Z
    if ($s3_time =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{3}))?Z?$/) {
        my ($year, $month, $day, $hour, $min, $sec, $msec) = ($1, $2, $3, $4, $5, $6, $7 // 0);
        
        eval {
            return timegm($sec, $min, $hour, $day, $month - 1, $year - 1900);
        };
        if ($@) {
            log_warn("Cannot parse S3 timestamp '$s3_time': $@");
            return 0;
        }
    }
    
    log_warn("Invalid S3 timestamp format: '$s3_time'");
    return 0;
}

# Formatage des tailles en bytes
sub format_bytes {
    my ($bytes) = @_;
    
    return '0 B' if !$bytes || $bytes == 0;
    
    my @units = ('B', 'KB', 'MB', 'GB', 'TB', 'PB');
    my $i = 0;
    
    while ($bytes >= 1024 && $i < @units - 1) {
        $bytes /= 1024;
        $i++;
    }
    
    return sprintf('%.2f %s', $bytes, $units[$i]);
}

# Validation du nom de bucket S3
sub validate_bucket_name {
    my ($bucket) = @_;
    
    return 0 if !$bucket;
    
    # Règles AWS S3 pour les noms de bucket
    return 0 if length($bucket) < 3 || length($bucket) > 63;
    return 0 if $bucket !~ /^[a-z0-9.-]+$/;
    return 0 if $bucket =~ /^\./ || $bucket =~ /\.$/;  # Ne peut pas commencer/finir par .
    return 0 if $bucket =~ /\.\./;                      # Pas de .. consécutifs
    return 0 if $bucket =~ /^(\d+\.){3}\d+$/;         # Pas d'adresse IP
    
    return 1;
}

# Validation du nom de clé S3
sub validate_key_name {
    my ($key) = @_;
    
    return 0 if !defined($key) || $key eq '';
    return 0 if length($key) > 1024;  # Limite AWS S3
    
    # Caractères interdits
    return 0 if $key =~ /[\x00-\x1f\x7f]/;  # Caractères de contrôle
    
    return 1;
}

# Parse et validation d'un endpoint S3
sub parse_endpoint {
    my ($endpoint) = @_;
    
    return undef if !$endpoint;
    
    # Ajout du schéma si manquant
    $endpoint = "https://$endpoint" if $endpoint !~ /^https?:\/\//;
    
    # Validation basique de l'URL
    if ($endpoint !~ /^https?:\/\/([^\/]+)(\/.*)?$/) {
        return undef;
    }
    
    my $host = $1;
    my $path = $2 // '';
    
    return {
        url => $endpoint,
        host => $host,
        path => $path,
        ssl => $endpoint =~ /^https:/,
    };
}

# Nettoyage et validation des métadonnées
sub sanitize_metadata {
    my ($metadata) = @_;
    
    return {} if !$metadata || ref($metadata) ne 'HASH';
    
    my $clean_metadata = {};
    
    foreach my $key (keys %$metadata) {
        # Nettoyage de la clé
        my $clean_key = $key;
        $clean_key =~ s/[^a-zA-Z0-9_-]/_/g;  # Remplace caractères invalides
        $clean_key = lc($clean_key);          # Minuscules
        
        # Nettoyage de la valeur
        my $value = $metadata->{$key} // '';
        $value =~ s/[\x00-\x1f\x7f]//g;      # Supprime caractères de contrôle
        $value = substr($value, 0, 2048);     # Limite à 2KB
        
        # Validation finale
        if (length($clean_key) > 0 && length($clean_key) <= 128) {
            $clean_metadata->{$clean_key} = $value;
        }
    }
    
    return $clean_metadata;
}

# Génération d'un ID unique pour les opérations
sub generate_operation_id {
    my $timestamp = time();
    my $random = int(rand(10000));
    my $pid = $$;
    
    return sprintf('%d_%d_%d', $timestamp, $pid, $random);
}

# Calcul du hash MD5 d'un fichier
sub file_md5_hex {
    my ($file_path) = @_;
    
    require Digest::MD5;
    
    open my $fh, '<:raw', $file_path or return undef;
    my $md5 = Digest::MD5->new();
    $md5->addfile($fh);
    close $fh;
    
    return $md5->hexdigest();
}

# Calcul du hash SHA256 d'un fichier
sub file_sha256_hex {
    my ($file_path) = @_;
    
    require Digest::SHA;
    
    open my $fh, '<:raw', $file_path or return undef;
    my $sha = Digest::SHA->new(256);
    $sha->addfile($fh);
    close $fh;
    
    return $sha->hexdigest();
}

# Vérification de l'espace disque disponible
sub check_disk_space {
    my ($path, $required_bytes) = @_;
    
    return 0 if !$path || !$required_bytes;
    
    # Utilise df pour obtenir l'espace disponible
    my $df_output = `df -B1 '$path' 2>/dev/null | tail -1`;
    return 0 if !$df_output;
    
    # Parse la sortie df
    if ($df_output =~ /\s+(\d+)\s+\d+\s+(\d+)\s+/) {
        my $available = $2;
        return $available >= $required_bytes;
    }
    
    return 0;
}

# Création d'un fichier temporaire sécurisé
sub create_temp_file {
    my ($prefix, $suffix) = @_;
    
    $prefix //= 'pve-s3';
    $suffix //= '.tmp';
    
    require File::Temp;
    my ($fh, $filename) = File::Temp::tempfile(
        "${prefix}_XXXXXX",
        SUFFIX => $suffix,
        DIR => '/tmp',
        UNLINK => 0,
    );
    
    close $fh if $fh;
    return $filename;
}

# Nettoyage des fichiers temporaires
sub cleanup_temp_files {
    my ($pattern) = @_;
    
    $pattern //= 'pve-s3*';
    
    eval {
        opendir(my $dh, '/tmp') or return;
        my @files = grep { /^$pattern/ && -f "/tmp/$_" } readdir($dh);
        closedir($dh);
        
        foreach my $file (@files) {
            my $full_path = "/tmp/$file";
            # Ne supprime que les fichiers plus vieux que 1 heure
            my $age = time() - (stat($full_path))[9];
            if ($age > 3600) {
                unlink $full_path;
            }
        }
    };
}

# Conversion d'un nom de volume Proxmox vers une clé S3
sub volname_to_s3_key {
    my ($volname, $prefix) = @_;
    
    $prefix //= '';
    $prefix =~ s|/+$|/| if $prefix;  # Normalise le slash final
    
    # Échappe les caractères spéciaux pour S3
    my $key = $volname;
    $key =~ s|/+|/|g;          # Normalise les slashes
    $key =~ s|^/||;            # Supprime le slash initial
    
    return $prefix . $key;
}

# Conversion d'une clé S3 vers un nom de volume Proxmox
sub s3_key_to_volname {
    my ($key, $prefix) = @_;
    
    $prefix //= '';
    
    if ($prefix) {
        $prefix =~ s|/+$|/|;   # Normalise le slash final
        $key =~ s/^\Q$prefix\E//;  # Supprime le préfixe
    }
    
    return $key;
}

1;