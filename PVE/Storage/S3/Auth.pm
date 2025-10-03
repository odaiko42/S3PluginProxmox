package PVE::Storage::S3::Auth;

use strict;
use warnings;

use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use MIME::Base64 qw(encode_base64);
use URI::Escape qw(uri_escape uri_escape_utf8);
use POSIX qw(strftime);
use Time::HiRes qw(time);

use PVE::Storage::S3::Utils qw(log_info log_warn log_error);
use PVE::Storage::S3::Exception qw(S3AuthException);

# Constructeur
sub new {
    my ($class, $params) = @_;
    
    $params //= {};
    
    my $self = {
        access_key => $params->{access_key},
        secret_key => $params->{secret_key},
        session_token => $params->{session_token},
        region => $params->{region} || 'us-east-1',
        service => 's3',
        algorithm => 'AWS4-HMAC-SHA256',
    };
    
    bless $self, $class;
    
    # Validation des credentials
    $self->_validate_credentials();
    
    return $self;
}

# Validation des credentials
sub _validate_credentials {
    my ($self) = @_;
    
    if (!$self->{access_key} || !$self->{secret_key}) {
        die S3AuthException("Access key and secret key are required");
    }
    
    if (length($self->{access_key}) < 16 || length($self->{access_key}) > 128) {
        die S3AuthException("Invalid access key format");
    }
    
    if (length($self->{secret_key}) < 40) {
        die S3AuthException("Invalid secret key format");
    }
    
    # Validation du format des clés
    if ($self->{access_key} !~ /^[A-Z0-9]+$/) {
        log_warn("Access key format may be invalid (should contain only uppercase letters and numbers)");
    }
}

# Signature d'une requête HTTP avec AWS Signature Version 4
sub sign_request {
    my ($self, $method, $uri, $headers, $body, $timestamp) = @_;
    
    $method = uc($method);
    $body //= '';
    $timestamp //= time();
    
    # Normalisation des headers
    $headers = $self->_normalize_headers($headers);
    
    # Génération du timestamp ISO8601
    my $iso8601_timestamp = $self->_format_timestamp($timestamp);
    my $date_stamp = substr($iso8601_timestamp, 0, 8);  # YYYYMMDD
    
    # Ajout des headers obligatoires
    $headers->{'host'} //= $self->_extract_host_from_uri($uri);
    $headers->{'x-amz-date'} = $iso8601_timestamp;
    
    if ($self->{session_token}) {
        $headers->{'x-amz-security-token'} = $self->{session_token};
    }
    
    # Calcul du hash du body
    my $body_hash = sha256_hex($body);
    $headers->{'x-amz-content-sha256'} = $body_hash;
    
    # Construction de la requête canonique
    my $canonical_request = $self->_build_canonical_request(
        $method, $uri, $headers, $body_hash
    );
    
    # Construction de la chaîne à signer
    my $credential_scope = "$date_stamp/$self->{region}/$self->{service}/aws4_request";
    my $string_to_sign = $self->_build_string_to_sign(
        $iso8601_timestamp, $credential_scope, $canonical_request
    );
    
    # Calcul de la signature
    my $signature = $self->_calculate_signature(
        $date_stamp, $string_to_sign
    );
    
    # Construction de l'en-tête Authorization
    my $signed_headers = join(';', sort keys %$headers);
    my $authorization = sprintf(
        '%s Credential=%s/%s, SignedHeaders=%s, Signature=%s',
        $self->{algorithm},
        $self->{access_key},
        $credential_scope,
        $signed_headers,
        $signature
    );
    
    $headers->{'authorization'} = $authorization;
    
    return $headers;
}

# Normalisation des headers HTTP
sub _normalize_headers {
    my ($self, $headers) = @_;
    
    $headers //= {};
    
    my $normalized = {};
    
    foreach my $key (keys %$headers) {
        my $lower_key = lc($key);
        my $value = $headers->{$key};
        
        # Nettoyage des espaces multiples
        $value =~ s/\s+/ /g;
        $value =~ s/^\s+|\s+$//g;
        
        $normalized->{$lower_key} = $value;
    }
    
    return $normalized;
}

# Extraction du host depuis l'URI
sub _extract_host_from_uri {
    my ($self, $uri) = @_;
    
    if ($uri =~ m{^https?://([^/]+)}) {
        return $1;
    }
    
    # Si pas de schéma, retourne tel quel
    return $uri;
}

# Formatage du timestamp
sub _format_timestamp {
    my ($self, $timestamp) = @_;
    
    my ($sec, $min, $hour, $mday, $mon, $year) = gmtime($timestamp);
    
    return sprintf(
        '%04d%02d%02dT%02d%02d%02dZ',
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec
    );
}

# Construction de la requête canonique
sub _build_canonical_request {
    my ($self, $method, $uri, $headers, $body_hash) = @_;
    
    # Parse de l'URI
    my ($path, $query) = split /\?/, $uri, 2;
    $path //= '/';
    $query //= '';
    
    # Encodage du chemin
    my $canonical_path = $self->_encode_path($path);
    
    # Tri et encodage des paramètres de query
    my $canonical_query = $self->_encode_query($query);
    
    # Construction des headers canoniques
    my $canonical_headers = '';
    my @sorted_headers = sort keys %$headers;
    
    foreach my $header (@sorted_headers) {
        $canonical_headers .= "$header:$headers->{$header}\n";
    }
    
    my $signed_headers = join(';', @sorted_headers);
    
    # Assemblage final
    return join("\n",
        $method,
        $canonical_path,
        $canonical_query,
        $canonical_headers,
        $signed_headers,
        $body_hash
    );
}

# Encodage du chemin selon RFC 3986
sub _encode_path {
    my ($self, $path) = @_;
    
    # Normalisation du chemin
    $path =~ s|/+|/|g;  # Supprime les slashes multiples
    $path = '/' if $path eq '';
    
    # Encodage segment par segment
    my @segments = split('/', $path);
    my @encoded_segments = ();
    
    foreach my $segment (@segments) {
        if ($segment ne '') {
            # Encodage URI avec préservation de certains caractères
            my $encoded = uri_escape_utf8($segment, "^A-Za-z0-9\-\._~");
            push @encoded_segments, $encoded;
        } else {
            push @encoded_segments, '';
        }
    }
    
    return join('/', @encoded_segments);
}

# Encodage des paramètres de query
sub _encode_query {
    my ($self, $query) = @_;
    
    return '' if !$query;
    
    my @params = split('&', $query);
    my @encoded_params = ();
    
    foreach my $param (@params) {
        my ($key, $value) = split('=', $param, 2);
        $key //= '';
        $value //= '';
        
        # Encodage des clés et valeurs
        $key = uri_escape_utf8($key, "^A-Za-z0-9\-\._~");
        $value = uri_escape_utf8($value, "^A-Za-z0-9\-\._~");
        
        push @encoded_params, "$key=$value";
    }
    
    # Tri par clé
    @encoded_params = sort @encoded_params;
    
    return join('&', @encoded_params);
}

# Construction de la chaîne à signer
sub _build_string_to_sign {
    my ($self, $timestamp, $credential_scope, $canonical_request) = @_;
    
    my $canonical_request_hash = sha256_hex($canonical_request);
    
    return join("\n",
        $self->{algorithm},
        $timestamp,
        $credential_scope,
        $canonical_request_hash
    );
}

# Calcul de la signature
sub _calculate_signature {
    my ($self, $date_stamp, $string_to_sign) = @_;
    
    # Clé de signature dérivée
    my $k_date = hmac_sha256($date_stamp, "AWS4" . $self->{secret_key});
    my $k_region = hmac_sha256($self->{region}, $k_date);
    my $k_service = hmac_sha256($self->{service}, $k_region);
    my $k_signing = hmac_sha256('aws4_request', $k_service);
    
    # Signature finale
    return hmac_sha256_hex($string_to_sign, $k_signing);
}

# Génération d'une URL présignée
sub generate_presigned_url {
    my ($self, $method, $uri, $expires, $headers) = @_;
    
    $method = uc($method);
    $expires //= 3600;  # 1 heure par défaut
    $headers //= {};
    
    my $timestamp = time();
    my $iso8601_timestamp = $self->_format_timestamp($timestamp);
    my $date_stamp = substr($iso8601_timestamp, 0, 8);
    
    # Construction des paramètres de query pour l'URL présignée
    my $credential_scope = "$date_stamp/$self->{region}/$self->{service}/aws4_request";
    my $credential = uri_escape("$self->{access_key}/$credential_scope");
    
    my @query_params = (
        "X-Amz-Algorithm=$self->{algorithm}",
        "X-Amz-Credential=$credential",
        "X-Amz-Date=$iso8601_timestamp",
        "X-Amz-Expires=$expires",
    );
    
    if ($self->{session_token}) {
        push @query_params, "X-Amz-Security-Token=" . uri_escape($self->{session_token});
    }
    
    # Ajout des signed headers si présents
    if (%$headers) {
        my $signed_headers = join(';', sort(map lc, keys %$headers));
        push @query_params, "X-Amz-SignedHeaders=" . uri_escape($signed_headers);
    }
    
    # Construction de l'URI temporaire pour la signature
    my $query_string = join('&', sort @query_params);
    my ($base_uri) = split(/\?/, $uri);
    my $temp_uri = "$base_uri?$query_string";
    
    # Calcul de la signature pour l'URL présignée
    my $canonical_request = $self->_build_canonical_request(
        $method, $temp_uri, $headers, 'UNSIGNED-PAYLOAD'
    );
    
    my $string_to_sign = $self->_build_string_to_sign(
        $iso8601_timestamp, $credential_scope, $canonical_request
    );
    
    my $signature = $self->_calculate_signature($date_stamp, $string_to_sign);
    
    # URL finale avec signature
    $query_string .= "&X-Amz-Signature=$signature";
    
    return "$base_uri?$query_string";
}

# Vérification de la validité des credentials (test avec une requête simple)
sub test_credentials {
    my ($self, $bucket) = @_;
    
    eval {
        # Test avec une requête HEAD simple
        my $headers = $self->sign_request('HEAD', "/$bucket", {});
        return 1;
    };
    
    if ($@) {
        log_error("Credential test failed: $@");
        return 0;
    }
    
    return 1;
}

# Accesseurs
sub access_key { return $_[0]->{access_key}; }
sub has_session_token { return defined $_[0]->{session_token}; }
sub region { return $_[0]->{region}; }

# Renouvellement des credentials temporaires
sub refresh_session_token {
    my ($self, $new_token) = @_;
    
    $self->{session_token} = $new_token;
    log_info("Session token refreshed");
}

# Information de debug (sans exposer les secrets)
sub debug_info {
    my ($self) = @_;
    
    return {
        access_key => substr($self->{access_key}, 0, 8) . '...',
        has_secret => defined $self->{secret_key},
        has_session_token => defined $self->{session_token},
        region => $self->{region},
        algorithm => $self->{algorithm},
    };
}

1;