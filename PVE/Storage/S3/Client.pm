package PVE::Storage::S3::Client;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use URI;
use JSON;
use XML::Simple;
use Time::HiRes qw(time);

use PVE::Storage::S3::Auth;
use PVE::Storage::S3::Config;
use PVE::Storage::S3::Transfer;
use PVE::Storage::S3::Utils qw(log_info log_warn log_error);
use PVE::Storage::S3::Exception qw(S3Exception S3ConnectionException S3BucketException handle_http_error with_retry);

# Constructeur
sub new {
    my ($class, $config, $auth) = @_;
    
    my $self = {
        config => $config,
        auth => $auth,
        ua => undef,
        transfer_manager => undef,
    };
    
    bless $self, $class;
    
    $self->_initialize_ua();
    $self->{transfer_manager} = PVE::Storage::S3::Transfer->new($self, $config);
    
    return $self;
}

# Initialisation du user agent HTTP
sub _initialize_ua {
    my ($self) = @_;
    
    $self->{ua} = LWP::UserAgent->new(
        timeout => $self->{config}->get('connection_timeout'),
        agent => 'Proxmox-S3-Plugin/1.0',
        ssl_opts => {
            verify_hostname => $self->{config}->get('verify_ssl'),
            SSL_verify_mode => $self->{config}->get('verify_ssl') ? 1 : 0,
        }
    );
    
    # Configuration du proxy si défini
    if (my $proxy = $ENV{HTTP_PROXY}) {
        $self->{ua}->proxy('http', $proxy);
    }
    if (my $proxy = $ENV{HTTPS_PROXY}) {
        $self->{ua}->proxy('https', $proxy);
    }
}

# Test de connectivité
sub test_connection {
    my ($self) = @_;
    
    eval {
        my $response = $self->_make_request('GET', '/');
        if (!$response->is_success && $response->code != 404) {
            die "Connection test failed: " . $response->status_line;
        }
    };
    if ($@) {
        die S3ConnectionException("Cannot connect to S3 endpoint: $@");
    }
    
    log_info("S3 connection test successful");
    return 1;
}

# Vérification de l'existence d'un bucket
sub head_bucket {
    my ($self, $bucket) = @_;
    
    my $response = $self->_make_request('HEAD', "/$bucket");
    
    if ($response->code == 404) {
        die S3BucketException("Bucket does not exist", $bucket);
    } elsif (!$response->is_success) {
        die handle_http_error($response, 'head_bucket');
    }
    
    return $self->_parse_headers($response);
}

# Création d'un bucket
sub create_bucket {
    my ($self, $bucket, $options) = @_;
    
    $options //= {};
    
    my $content = '';
    my $region = $self->{config}->get('region');
    
    # Configuration XML pour la région (si différente de us-east-1)
    if ($region && $region ne 'us-east-1') {
        $content = qq{<?xml version="1.0" encoding="UTF-8"?>
<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <LocationConstraint>$region</LocationConstraint>
</CreateBucketConfiguration>};
    }
    
    my $headers = {
        'Content-Type' => 'application/xml',
        'Content-Length' => length($content),
    };
    
    # ACL du bucket si spécifié
    if ($options->{acl}) {
        $headers->{'x-amz-acl'} = $options->{acl};
    }
    
    my $response = $self->_make_request('PUT', "/$bucket", $headers, $content);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'create_bucket');
    }
    
    log_info("Bucket created successfully: $bucket");
    return 1;
}

# Liste des objets dans un bucket
sub list_objects {
    my ($self, $bucket, $prefix, $options) = @_;
    
    $options //= {};
    $prefix //= '';
    
    my $max_keys = $options->{max_keys} || 1000;
    my $all_objects = [];
    my $continuation_token = '';
    
    do {
        my %params = (
            'list-type' => '2',
            'max-keys' => $max_keys,
        );
        
        $params{prefix} = $prefix if $prefix;
        $params{'continuation-token'} = $continuation_token if $continuation_token;
        
        my $query_string = $self->_build_query_string(\%params);
        my $response = $self->_make_request('GET', "/$bucket?$query_string");
        
        if (!$response->is_success) {
            die handle_http_error($response, 'list_objects');
        }
        
        # Parse de la réponse XML
        my $xml_data = $response->content;
        my $parsed = $self->_parse_list_objects_xml($xml_data);
        
        push @$all_objects, @{$parsed->{objects}};
        $continuation_token = $parsed->{next_continuation_token} || '';
        
    } while ($continuation_token && @$all_objects < ($options->{limit} || 10000));
    
    return $all_objects;
}

# Récupération des métadonnées d'un objet
sub head_object {
    my ($self, $bucket, $key) = @_;
    
    my $response = $self->_make_request('HEAD', "/$bucket/$key");
    
    if ($response->code == 404) {
        die S3Exception("Object not found: $key");
    } elsif (!$response->is_success) {
        die handle_http_error($response, 'head_object');
    }
    
    return $self->_parse_headers($response);
}

# Upload d'un objet (PUT)
sub put_object {
    my ($self, $bucket, $key, $content, $headers) = @_;
    
    $headers //= {};
    $headers->{'Content-Length'} = length($content);
    
    # Ajout des headers par défaut
    my $default_headers = $self->{config}->default_headers();
    %$headers = (%$default_headers, %$headers);
    
    my $response = $self->_make_request('PUT', "/$bucket/$key", $headers, $content);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'put_object');
    }
    
    return {
        ETag => $response->header('ETag'),
        VersionId => $response->header('x-amz-version-id'),
    };
}

# Téléchargement d'un objet
sub get_object {
    my ($self, $bucket, $key, $output_file) = @_;
    
    my $response = $self->_make_request('GET', "/$bucket/$key");
    
    if (!$response->is_success) {
        die handle_http_error($response, 'get_object');
    }
    
    if ($output_file) {
        open my $fh, '>:raw', $output_file or die "Cannot create output file: $!";
        print $fh $response->content;
        close $fh;
    }
    
    return $response->content;
}

# Téléchargement d'une range d'un objet
sub get_object_range {
    my ($self, $bucket, $key, $range_start, $range_end) = @_;
    
    my $headers = {
        'Range' => "bytes=$range_start-$range_end",
    };
    
    my $response = $self->_make_request('GET', "/$bucket/$key", $headers);
    
    if ($response->code != 206 && $response->code != 200) {
        die handle_http_error($response, 'get_object_range');
    }
    
    return $response->content;
}

# Suppression d'un objet
sub delete_object {
    my ($self, $bucket, $key) = @_;
    
    my $response = $self->_make_request('DELETE', "/$bucket/$key");
    
    if (!$response->is_success && $response->code != 404) {
        die handle_http_error($response, 'delete_object');
    }
    
    log_info("Object deleted: s3://$bucket/$key");
    return 1;
}

# Copie d'un objet
sub copy_object {
    my ($self, $source_bucket, $source_key, $dest_bucket, $dest_key, $options) = @_;
    
    $options //= {};
    
    my $headers = {
        'x-amz-copy-source' => "/$source_bucket/$source_key",
    };
    
    # Directive de métadonnées
    if ($options->{metadata_directive}) {
        $headers->{'x-amz-metadata-directive'} = $options->{metadata_directive};
    }
    
    # Nouvelles métadonnées si REPLACE
    if ($options->{metadata}) {
        foreach my $key (keys %{$options->{metadata}}) {
            $headers->{"x-amz-meta-$key"} = $options->{metadata}->{$key};
        }
    }
    
    my $response = $self->_make_request('PUT', "/$dest_bucket/$dest_key", $headers);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'copy_object');
    }
    
    return { ETag => $response->header('ETag') };
}

# Initiation d'un multipart upload
sub initiate_multipart_upload {
    my ($self, $bucket, $key, $options) = @_;
    
    $options //= {};
    
    my $headers = $self->{config}->default_headers();
    
    # Ajout des métadonnées si spécifiées
    if ($options->{metadata}) {
        foreach my $meta_key (keys %{$options->{metadata}}) {
            $headers->{"x-amz-meta-$meta_key"} = $options->{metadata}->{$meta_key};
        }
    }
    
    my $response = $self->_make_request('POST', "/$bucket/$key?uploads", $headers);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'initiate_multipart_upload');
    }
    
    # Parse de l'upload ID depuis la réponse XML
    my $xml = $response->content;
    if ($xml =~ /<UploadId>([^<]+)<\/UploadId>/) {
        return $1;
    } else {
        die S3Exception("Cannot parse upload ID from response");
    }
}

# Upload d'une part
sub upload_part {
    my ($self, $bucket, $key, $upload_id, $part_number, $data) = @_;
    
    my $headers = {
        'Content-Length' => length($data),
        'Content-Type' => 'application/octet-stream',
    };
    
    my $url = "/$bucket/$key?partNumber=$part_number&uploadId=$upload_id";
    my $response = $self->_make_request('PUT', $url, $headers, $data);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'upload_part');
    }
    
    return $response->header('ETag');
}

# Finalisation d'un multipart upload
sub complete_multipart_upload {
    my ($self, $bucket, $key, $upload_id, $parts) = @_;
    
    # Construction du XML des parts
    my $xml_parts = '';
    foreach my $part (@$parts) {
        $xml_parts .= "<Part><PartNumber>$part->{PartNumber}</PartNumber><ETag>$part->{ETag}</ETag></Part>";
    }
    
    my $xml_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $xml_content .= "<CompleteMultipartUpload>$xml_parts</CompleteMultipartUpload>";
    
    my $headers = {
        'Content-Type' => 'application/xml',
        'Content-Length' => length($xml_content),
    };
    
    my $url = "/$bucket/$key?uploadId=$upload_id";
    my $response = $self->_make_request('POST', $url, $headers, $xml_content);
    
    if (!$response->is_success) {
        die handle_http_error($response, 'complete_multipart_upload');
    }
    
    return { ETag => $response->header('ETag') };
}

# Annulation d'un multipart upload
sub abort_multipart_upload {
    my ($self, $bucket, $key, $upload_id) = @_;
    
    my $url = "/$bucket/$key?uploadId=$upload_id";
    my $response = $self->_make_request('DELETE', $url);
    
    if (!$response->is_success) {
        log_warn("Failed to abort multipart upload: " . $response->status_line);
    }
    
    return 1;
}

# Interface de haut niveau pour upload de fichier
sub upload_file {
    my ($self, $local_file, $bucket, $key, $options) = @_;
    
    return $self->{transfer_manager}->upload_file($local_file, $bucket, $key, $options);
}

# Interface de haut niveau pour download de fichier
sub download_file {
    my ($self, $bucket, $key, $local_file, $options) = @_;
    
    return $self->{transfer_manager}->download_file($bucket, $key, $local_file, $options);
}

# Génération d'une URL présignée
sub generate_presigned_url {
    my ($self, $method, $bucket, $key, $expires, $options) = @_;
    
    my $uri = "/$bucket/$key";
    return $self->{auth}->generate_presigned_url($method, $uri, $expires, $options->{headers});
}

# Requête HTTP de base
sub _make_request {
    my ($self, $method, $uri, $headers, $content) = @_;
    
    $headers //= {};
    $content //= '';
    
    # Construction de l'URL complète
    my $url = $self->{config}->endpoint_url() . $uri;
    
    # Signature de la requête
    my $signed_headers = $self->{auth}->sign_request($method, $uri, $headers, $content);
    
    # Création de la requête HTTP
    my $request = HTTP::Request->new($method, $url);
    
    # Ajout des headers
    foreach my $header_name (keys %$signed_headers) {
        $request->header($header_name, $signed_headers->{$header_name});
    }
    
    # Ajout du contenu
    $request->content($content) if $content;
    
    # Envoi de la requête avec retry automatique
    return with_retry(sub {
        my $response = $self->{ua}->request($request);
        
        # Log de debug si activé
        if ($ENV{PVE_S3_DEBUG}) {
            log_info("S3 Request: $method $uri -> " . $response->code);
        }
        
        return $response;
    });
}

# Construction d'une query string
sub _build_query_string {
    my ($self, $params) = @_;
    
    my @parts = ();
    foreach my $key (sort keys %$params) {
        my $value = $params->{$key};
        if (defined $value && $value ne '') {
            push @parts, "$key=" . URI::Escape::uri_escape($value);
        } else {
            push @parts, $key;
        }
    }
    
    return join('&', @parts);
}

# Parse des headers de réponse
sub _parse_headers {
    my ($self, $response) = @_;
    
    my $headers = {};
    
    # Headers standard
    $headers->{ContentLength} = $response->header('Content-Length');
    $headers->{ContentType} = $response->header('Content-Type');
    $headers->{ETag} = $response->header('ETag');
    $headers->{LastModified} = $response->header('Last-Modified');
    
    # Métadonnées utilisateur (x-amz-meta-*)
    foreach my $header_name ($response->header_field_names) {
        if ($header_name =~ /^x-amz-meta-(.+)$/i) {
            $headers->{$header_name} = $response->header($header_name);
        }
    }
    
    return $headers;
}

# Parse du XML de liste d'objets
sub _parse_list_objects_xml {
    my ($self, $xml) = @_;
    
    my @objects = ();
    my $next_token = '';
    
    # Parse simple sans XML::Simple pour éviter les dépendances
    while ($xml =~ /<Contents>(.*?)<\/Contents>/gs) {
        my $content_xml = $1;
        
        my %object = ();
        if ($content_xml =~ /<Key>([^<]+)<\/Key>/) {
            $object{Key} = $1;
        }
        if ($content_xml =~ /<Size>([^<]+)<\/Size>/) {
            $object{Size} = $1;
        }
        if ($content_xml =~ /<LastModified>([^<]+)<\/LastModified>/) {
            $object{LastModified} = $1;
        }
        if ($content_xml =~ /<ETag>([^<]+)<\/ETag>/) {
            $object{ETag} = $1;
        }
        
        push @objects, \%object if $object{Key};
    }
    
    # Token de continuation
    if ($xml =~ /<NextContinuationToken>([^<]+)<\/NextContinuationToken>/) {
        $next_token = $1;
    }
    
    return {
        objects => \@objects,
        next_continuation_token => $next_token,
    };
}

# Accesseurs
sub config { return $_[0]->{config}; }
sub auth { return $_[0]->{auth}; }
sub transfer_manager { return $_[0]->{transfer_manager}; }

1;