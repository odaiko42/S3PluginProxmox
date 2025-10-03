package PVE::Storage::Custom::S3Client;

use strict;
use warnings;

use HTTP::Request;
use LWP::UserAgent;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use MIME::Base64;
use POSIX qw(strftime);
use URI::Escape;
use XML::LibXML;

# Constructeur
sub new {
    my ($class, %params) = @_;
    
    my $self = {
        endpoint => $params{endpoint} || die "endpoint required",
        region => $params{region} || 'us-east-1',
        access_key => $params{access_key} || die "access_key required",
        secret_key => $params{secret_key} || die "secret_key required",
        bucket => $params{bucket} || die "bucket required",
        prefix => $params{prefix} || '',
        ua => LWP::UserAgent->new(timeout => 30),
    };
    
    bless $self, $class;
    return $self;
}

# Signature AWS V4
sub _sign_request {
    my ($self, $method, $uri, $headers, $payload) = @_;
    
    my $now = time();
    my $date_stamp = strftime('%Y%m%d', gmtime($now));
    my $date_time = strftime('%Y%m%dT%H%M%SZ', gmtime($now));
    
    # En-têtes obligatoires
    $headers->{'host'} = $self->{endpoint};
    $headers->{'x-amz-date'} = $date_time;
    $headers->{'x-amz-content-sha256'} = sha256_hex($payload || '');
    
    # Canonical request
    my @signed_headers = sort keys %$headers;
    my $canonical_headers = join('', map { lc($_) . ':' . $headers->{$_} . "\n" } @signed_headers);
    my $signed_headers_str = join(';', map { lc($_) } @signed_headers);
    
    my $canonical_request = join("\n",
        $method,
        $uri,
        '', # query string (vide pour l'instant)
        $canonical_headers,
        $signed_headers_str,
        sha256_hex($payload || '')
    );
    
    # String to sign
    my $algorithm = 'AWS4-HMAC-SHA256';
    my $credential_scope = "$date_stamp/" . $self->{region} . "/s3/aws4_request";
    my $string_to_sign = join("\n",
        $algorithm,
        $date_time,
        $credential_scope,
        sha256_hex($canonical_request)
    );
    
    # Signature
    my $k_date = hmac_sha256($date_stamp, 'AWS4' . $self->{secret_key});
    my $k_region = hmac_sha256($self->{region}, $k_date);
    my $k_service = hmac_sha256('s3', $k_region);
    my $k_signing = hmac_sha256('aws4_request', $k_service);
    my $signature = hmac_sha256_hex($string_to_sign, $k_signing);
    
    # Authorization header
    my $authorization = sprintf('%s Credential=%s/%s, SignedHeaders=%s, Signature=%s',
        $algorithm,
        $self->{access_key},
        $credential_scope,
        $signed_headers_str,
        $signature
    );
    
    $headers->{'Authorization'} = $authorization;
    
    return $headers;
}

# Requête HTTP S3 générique
sub _s3_request {
    my ($self, $method, $path, $payload, $extra_headers) = @_;
    
    $path = '/' . $self->{bucket} . $path if $path !~ m|^/|;
    my $url = 'https://' . $self->{endpoint} . $path;
    
    my $headers = $extra_headers || {};
    $headers = $self->_sign_request($method, $path, $headers, $payload);
    
    my $request = HTTP::Request->new($method, $url);
    
    # Ajouter les en-têtes
    foreach my $key (keys %$headers) {
        $request->header($key, $headers->{$key});
    }
    
    $request->content($payload) if $payload;
    
    my $response = $self->{ua}->request($request);
    
    return $response;
}

# Lister les objets du bucket
sub list_objects {
    my ($self, $prefix_filter) = @_;
    
    my $prefix = $self->{prefix} . ($prefix_filter || '');
    my $path = '/' . $self->{bucket} . '?list-type=2';
    $path .= '&prefix=' . uri_escape($prefix) if $prefix;
    
    my $response = $self->_s3_request('GET', $path);
    
    if (!$response->is_success) {
        die "S3 list failed: " . $response->status_line . " - " . $response->content;
    }
    
    # Parser la réponse XML
    my $parser = XML::LibXML->new();
    my $doc = eval { $parser->parse_string($response->content) };
    if ($@) {
        die "Failed to parse S3 response: $@";
    }
    
    my @objects;
    my $root = $doc->documentElement();
    
    foreach my $content ($root->findnodes('//Contents')) {
        my $key = $content->findvalue('Key');
        my $size = $content->findvalue('Size');
        my $modified = $content->findvalue('LastModified');
        
        # Enlever le prefix du nom
        $key =~ s/^\Q$self->{prefix}\E// if $self->{prefix};
        
        push @objects, {
            key => $key,
            size => $size + 0,
            modified => $modified,
        };
    }
    
    return \@objects;
}

# Obtenir les informations d'un objet
sub head_object {
    my ($self, $key) = @_;
    
    my $full_key = $self->{prefix} . $key;
    my $path = '/' . $self->{bucket} . '/' . uri_escape($full_key);
    
    my $response = $self->_s3_request('HEAD', $path);
    
    if ($response->code == 404) {
        return undef; # Objet n'existe pas
    }
    
    if (!$response->is_success) {
        die "S3 head failed: " . $response->status_line;
    }
    
    return {
        size => $response->header('Content-Length') + 0,
        modified => $response->header('Last-Modified'),
        etag => $response->header('ETag'),
    };
}

# Upload d'un fichier
sub put_object {
    my ($self, $key, $file_path) = @_;
    
    my $full_key = $self->{prefix} . $key;
    my $path = '/' . $self->{bucket} . '/' . uri_escape($full_key);
    
    # Lire le fichier
    open my $fh, '<:raw', $file_path or die "Cannot open $file_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    my $headers = {
        'Content-Type' => 'application/octet-stream',
        'Content-Length' => length($content),
    };
    
    my $response = $self->_s3_request('PUT', $path, $content, $headers);
    
    if (!$response->is_success) {
        die "S3 upload failed: " . $response->status_line . " - " . $response->content;
    }
    
    return $response->header('ETag');
}

# Download d'un fichier  
sub get_object {
    my ($self, $key, $file_path) = @_;
    
    my $full_key = $self->{prefix} . $key;
    my $path = '/' . $self->{bucket} . '/' . uri_escape($full_key);
    
    my $response = $self->_s3_request('GET', $path);
    
    if (!$response->is_success) {
        die "S3 download failed: " . $response->status_line . " - " . $response->content;
    }
    
    # Écrire le fichier
    open my $fh, '>:raw', $file_path or die "Cannot create $file_path: $!";
    print $fh $response->content;
    close $fh;
    
    return length($response->content);
}

# Supprimer un objet
sub delete_object {
    my ($self, $key) = @_;
    
    my $full_key = $self->{prefix} . $key;
    my $path = '/' . $self->{bucket} . '/' . uri_escape($full_key);
    
    my $response = $self->_s3_request('DELETE', $path);
    
    if (!$response->is_success && $response->code != 404) {
        die "S3 delete failed: " . $response->status_line . " - " . $response->content;
    }
    
    return 1;
}

# Test de connectivité
sub test_connection {
    my ($self) = @_;
    
    eval {
        my $objects = $self->list_objects('');
        return 1;
    };
    
    if ($@) {
        return (0, $@);
    }
    
    return (1, 'OK');
}

1;