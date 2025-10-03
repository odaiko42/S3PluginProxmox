package PVE::Storage::Custom::S3Plugin;

use v5.34; # strict + warnings
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use IO::File;
use POSIX qw(:errno_h);
use Time::HiRes qw(gettimeofday);
use JSON;
use LWP::UserAgent;
use HTTP::Request;
use Digest::SHA qw(hmac_sha256_hex sha256_hex);
use POSIX qw(strftime);
use URI::Escape qw(uri_escape);

use PVE::ProcFSTools;
use PVE::INotify;
use PVE::Tools qw(
    file_copy
    file_get_contents
    file_set_contents
    run_command
);
use Encode qw(encode decode);

use base qw(PVE::Storage::Plugin);

# Plugin Definition
sub api { return 12; }
sub type { return 's3'; }

sub plugindata {
    return {
        content => [
            {
                images   => 1,
                rootdir  => 1,
                vztmpl   => 1,
                iso      => 1,
                backup   => 1,
                snippets => 1,
            },
        ],
        format => [
            { raw => 1 },
            { qcow2 => 1 },
            { vmdk => 1 },
        ],
        'sensitive-properties' => { secret_key => 1 },
        default_options => { 
            s3_port => 9000,
            use_ssl => 0,
            create_bucket => 1,
        },
    };
}

sub properties {
    return {
        endpoint => {
           description => "S3 endpoint URL (e.g., s3.amazonaws.com or 192.168.1.100:9000)",
           type => 'string',
        },
        bucket => {
           description => "S3 bucket name",
           type => 'string',
        },
        access_key => {
            description => "S3 access key ID",
            type        => 'string',
        },
        secret_key => {
            description => "S3 secret access key",
            type        => 'string',
        },
        region => {
            description => "S3 region (default: us-east-1)",
            type        => 'string',
            default     => 'us-east-1',
        },
        s3_port => {
            description => "S3 endpoint port (default: 9000 for MinIO, 443 for HTTPS, 80 for HTTP)",
            type        => 'integer',
            default     => 9000,
        },
        use_ssl => {
            description => "Use HTTPS for S3 connections",
            type        => 'boolean',
            default     => 0,
        },
        create_bucket => {
            description => "Create bucket if it doesn't exist",
            type        => 'boolean',
            default     => 1,
        },
        prefix => {
            description => "S3 object key prefix (subdirectory)",
            type        => 'string',
            default     => '',
        },
        max_backups => {
            description => "Maximum number of backups to keep per VM",
            type        => 'integer',
            default     => 5,
        },
    };
}

sub options {
    return {
        disable             => { optional => 1 },
        'create-base-path'  => { optional => 1 },
        content             => { optional => 1 },
        'create-subdirs'    => { optional => 1 },
        'content-dirs'      => { optional => 1 },
        'prune-backups'     => { optional => 1 },
        'max-protected-backups' => { optional => 1 },
        format              => { optional => 1 },
        bwlimit             => { optional => 1 },
        preallocation       => { optional => 1 },
        nodes               => { optional => 1 },
        shared              => { optional => 1 },

        # S3 Options
        endpoint       => {},
        bucket         => {},
        access_key     => {},
        secret_key     => {},
        region         => { optional => 1 },
        s3_port        => { optional => 1 },
        use_ssl        => { optional => 1 },
        create_bucket  => { optional => 1 },
        prefix         => { optional => 1 },
        max_backups    => { optional => 1 },
    };
}

# -----------------------------
# S3 Helpers
# -----------------------------

sub s3_get_config {
    my ($scfg) = @_;
    
    my $endpoint = $scfg->{endpoint};
    my $port = $scfg->{s3_port} // 9000;
    my $use_ssl = $scfg->{use_ssl} // 0;
    
    # Construction de l'URL de base
    my $protocol = $use_ssl ? 'https' : 'http';
    my $base_url = "$protocol://$endpoint";
    
    # Ajouter le port seulement s'il n'est pas standard
    if (($use_ssl && $port != 443) || (!$use_ssl && $port != 80)) {
        $base_url .= ":$port";
    }
    
    return {
        endpoint => $endpoint,
        bucket => $scfg->{bucket},
        access_key => $scfg->{access_key},
        secret_key => $scfg->{secret_key},
        region => $scfg->{region} // 'us-east-1',
        s3_port => $port,
        use_ssl => $use_ssl,
        base_url => $base_url,
        prefix => $scfg->{prefix} // '',
    };
}

sub s3_sign_request {
    my ($config, $method, $path, $headers, $payload) = @_;
    
    $headers = {} unless $headers;
    $payload = '' unless defined $payload;
    
    # AWS Signature Version 4
    my $algorithm = 'AWS4-HMAC-SHA256';
    my $service = 's3';
    my $region = $config->{region};
    my $access_key = $config->{access_key};
    my $secret_key = $config->{secret_key};
    
    # Date et timestamp
    my $t = time();
    my $date = strftime('%Y%m%d', gmtime($t));
    my $timestamp = strftime('%Y%m%dT%H%M%SZ', gmtime($t));
    
    # Headers obligatoires
    $headers->{'Host'} = $config->{endpoint};
    $headers->{'Host'} .= ":$config->{s3_port}" if $config->{s3_port} != 80 && $config->{s3_port} != 443;
    $headers->{'X-Amz-Date'} = $timestamp;
    $headers->{'X-Amz-Content-Sha256'} = sha256_hex($payload);
    
    # Canonical request
    my $canonical_headers = '';
    my $signed_headers = '';
    for my $header (sort keys %$headers) {
        my $lc_header = lc($header);
        $canonical_headers .= "$lc_header:" . $headers->{$header} . "\n";
        $signed_headers .= "$lc_header;";
    }
    $signed_headers =~ s/;$//;
    
    my $canonical_request = join("\n",
        $method,
        $path,
        '', # query string
        $canonical_headers,
        $signed_headers,
        $headers->{'X-Amz-Content-Sha256'}
    );
    
    # String to sign
    my $credential_scope = "$date/$region/$service/aws4_request";
    my $string_to_sign = join("\n",
        $algorithm,
        $timestamp,
        $credential_scope,
        sha256_hex($canonical_request)
    );
    
    # Signature
    my $date_key = hmac_sha256_hex($date, "AWS4$secret_key");
    my $region_key = hmac_sha256_hex($region, pack('H*', $date_key));
    my $service_key = hmac_sha256_hex($service, pack('H*', $region_key));
    my $signing_key = hmac_sha256_hex('aws4_request', pack('H*', $service_key));
    my $signature = hmac_sha256_hex($string_to_sign, pack('H*', $signing_key));
    
    # Authorization header
    my $authorization = "$algorithm " .
        "Credential=$access_key/$credential_scope, " .
        "SignedHeaders=$signed_headers, " .
        "Signature=$signature";
    
    $headers->{'Authorization'} = $authorization;
    
    return $headers;
}

sub s3_request {
    my ($config, $method, $path, $headers, $content) = @_;
    
    $headers = {} unless $headers;
    $content = '' unless defined $content;
    
    # Signer la requête
    $headers = s3_sign_request($config, $method, $path, $headers, $content);
    
    # Construire l'URL complète
    my $url = $config->{base_url} . $path;
    
    # Créer et exécuter la requête
    my $ua = LWP::UserAgent->new(timeout => 30);
    my $request = HTTP::Request->new($method, $url, [%$headers], $content);
    
    my $response = $ua->request($request);
    
    return $response;
}

sub s3_bucket_exists {
    my ($config) = @_;
    
    my $path = "/$config->{bucket}";
    my $response = s3_request($config, 'HEAD', $path);
    
    return $response->is_success;
}

sub s3_create_bucket {
    my ($config) = @_;
    
    return 1 if s3_bucket_exists($config);
    
    my $path = "/$config->{bucket}";
    my $response = s3_request($config, 'PUT', $path);
    
    if (!$response->is_success) {
        die "Failed to create S3 bucket '$config->{bucket}': " . $response->status_line . "\n";
    }
    
    return 1;
}

sub s3_list_objects {
    my ($config, $prefix) = @_;
    
    $prefix = $config->{prefix} . ($prefix // '');
    
    my $path = "/$config->{bucket}";
    $path .= "?list-type=2";
    $path .= "&prefix=" . uri_escape($prefix) if $prefix;
    
    my $response = s3_request($config, 'GET', $path);
    
    if (!$response->is_success) {
        die "Failed to list S3 objects: " . $response->status_line . "\n";
    }
    
    # Parse XML response (simplified)
    my $content = $response->decoded_content;
    my @objects = ();
    
    # Simple regex parsing pour les objets
    while ($content =~ /<Contents>.*?<Key>(.*?)<\/Key>.*?<Size>(\d+)<\/Size>.*?<LastModified>(.*?)<\/LastModified>.*?<\/Contents>/gs) {
        my ($key, $size, $modified) = ($1, $2, $3);
        
        # Retirer le préfixe pour obtenir le nom relatif
        $key =~ s/^\Q$prefix\E// if $prefix;
        
        push @objects, {
            key => $key,
            size => $size,
            modified => $modified,
        };
    }
    
    return \@objects;
}

sub s3_object_exists {
    my ($config, $key) = @_;
    
    $key = $config->{prefix} . $key if $config->{prefix};
    my $path = "/$config->{bucket}/" . uri_escape($key);
    
    my $response = s3_request($config, 'HEAD', $path);
    
    return $response->is_success;
}

sub s3_delete_object {
    my ($config, $key) = @_;
    
    $key = $config->{prefix} . $key if $config->{prefix};
    my $path = "/$config->{bucket}/" . uri_escape($key);
    
    my $response = s3_request($config, 'DELETE', $path);
    
    if (!$response->is_success && $response->code != 404) {
        die "Failed to delete S3 object '$key': " . $response->status_line . "\n";
    }
    
    return 1;
}

# -----------------------------
# Storage Implementation
# -----------------------------

sub on_add_hook {
    my ($class, $storeid, $scfg, %sensitive) = @_;
    $scfg->{shared} = 1;
    return undef;
}

sub on_update_hook {
    my ($class, $storeid, $scfg, %sensitive) = @_;
    return undef;
}

sub on_delete_hook {
    my ($class, $storeid, $scfg) = @_;
    # Rien à faire pour S3, pas de montage à défaire
    return undef;
}

sub check_connection {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $config = s3_get_config($scfg);
    
    # Vérifier que le bucket existe ou peut être créé
    eval {
        if (!s3_bucket_exists($config)) {
            if ($scfg->{create_bucket} // 1) {
                s3_create_bucket($config);
            } else {
                die "S3 bucket '$config->{bucket}' does not exist";
            }
        }
    };
    
    return $@ ? 0 : 1;
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $config = s3_get_config($scfg);
    
    # Vérifier la connectivité et créer le bucket si nécessaire
    if (!s3_bucket_exists($config)) {
        if ($scfg->{create_bucket} // 1) {
            s3_create_bucket($config);
        } else {
            die "unable to activate storage '$storeid' - S3 bucket '$config->{bucket}' does not exist\n";
        }
    }
    
    $class->SUPER::activate_storage($storeid, $scfg, $cache);
    return;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    # Rien à faire pour S3
    return;
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    
    my $config = s3_get_config($scfg);
    
    # Vérifier la connectivité
    return undef unless s3_bucket_exists($config);
    
    # Pour S3, on retourne des valeurs par défaut car l'espace n'est pas limité
    return (1000000000000, 1000000000000, 0, 1);  # 1TB total, 1TB available, 0 used, active
}

sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;
    
    my $config = s3_get_config($scfg);
    my $prefix = $config->{prefix};
    
    # Construire le chemin S3
    my $path = $prefix;
    
    if (defined($volname)) {
        my ($vtype) = $class->parse_volname($volname);
        if ($vtype eq 'images') {
            $path .= 'images/';
        } elsif ($vtype eq 'iso') {
            $path .= 'template/iso/';
        } elsif ($vtype eq 'backup') {
            $path .= 'dump/';
        } elsif ($vtype eq 'vztmpl') {
            $path .= 'template/cache/';
        } elsif ($vtype eq 'snippets') {
            $path .= 'snippets/';
        }
        
        # Ajouter le nom du fichier
        if ($volname !~ /\/$/) {
            my (undef, $name) = $class->parse_volname($volname);
            $path .= $name if $name;
        }
    }
    
    return wantarray ? ($path, undef, undef) : $path;
}

sub volume_list {
    my ($class, $storeid, $scfg, $vmid, $content_types) = @_;
    
    my $config = s3_get_config($scfg);
    my @volumes = ();
    
    # Lister les objets selon les types de contenu demandés
    if ($content_types && grep { $_ eq 'backup' } @$content_types) {
        my $objects = s3_list_objects($config, 'dump/');
        for my $obj (@$objects) {
            next unless $obj->{key} =~ /^vzdump-(qemu|lxc)-(\d+)-\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}\.(vma\.zst|vma\.gz|vma|tar\.zst|tar\.gz|tar)$/;
            my ($type, $backup_vmid) = ($1, $2);
            next if $vmid && $vmid != $backup_vmid;
            
            push @volumes, {
                volid => "$storeid:backup/$obj->{key}",
                format => 'raw',
                size => $obj->{size},
                vmid => $backup_vmid,
                ctime => 0,  # S3 ne fournit pas facilement ctime
                type => $type,
            };
        }
    }
    
    return \@volumes;
}

sub volume_size {
    my ($class, $storeid, $scfg, $volname) = @_;
    
    my $config = s3_get_config($scfg);
    my $key = $class->path($scfg, $volname);
    
    # Obtenir les métadonnées de l'objet
    $key = $config->{prefix} . $key if $config->{prefix};
    my $path = "/$config->{bucket}/" . uri_escape($key);
    
    my $response = s3_request($config, 'HEAD', $path);
    
    if ($response->is_success) {
        return $response->header('Content-Length') || 0;
    }
    
    return 0;
}

sub free_storage {
    my ($class, $storeid, $scfg, $volname) = @_;
    
    my $config = s3_get_config($scfg);
    my $key = $class->path($scfg, $volname);
    
    s3_delete_object($config, $key);
    
    return undef;
}

sub parse_volname {
    my ($class, $volname) = @_;
    
    # Handle backup volumes
    if ($volname =~ m!^backup/(.+)$!) {
        return ('backup', $1);
    }
    
    # Handle ISO volumes
    if ($volname =~ m!^iso/(.+\.iso)$!) {
        return ('iso', $1);
    }
    
    # Handle container template volumes
    if ($volname =~ m!^vztmpl/(.+\.tar\.[gx]z)$!) {
        return ('vztmpl', $1);
    }
    
    # Handle VM images
    if ($volname =~ m!^images/(\d+)/(.+)$!) {
        return ('images', "$1/$2");
    }
    
    # Handle snippets
    if ($volname =~ m!^snippets/(.+)$!) {
        return ('snippets', $1);
    }
    
    # Default case - try to determine from extension
    if ($volname =~ /\.iso$/) {
        return ('iso', $volname);
    } elsif ($volname =~ /\.tar\.[gx]z$/) {
        return ('vztmpl', $volname);
    } elsif ($volname =~ /^vzdump-/) {
        return ('backup', $volname);
    }
    
    # Default to images
    return ('images', $volname);
}

1;