package PVE::Storage::S3::Config;

use strict;
use warnings;

use PVE::Storage::S3::Utils qw(log_info log_warn log_error parse_endpoint validate_bucket_name);
use PVE::Storage::S3::Exception qw(S3ConfigException);

# Configuration par défaut
my %DEFAULT_CONFIG = (
    # Paramètres de connexion
    region => 'us-east-1',
    connection_timeout => 60,
    read_timeout => 300,
    max_retries => 3,
    
    # Paramètres de transfert
    multipart_chunk_size => 100 * 1024 * 1024,  # 100MB
    max_concurrent_uploads => 3,
    max_concurrent_downloads => 3,
    
    # Paramètres de sécurité
    use_ssl => 1,
    verify_ssl => 1,
    
    # Paramètres de stockage
    storage_class => 'STANDARD',
    prefix => 'proxmox/',
    
    # Paramètres de cycle de vie
    lifecycle_enabled => 0,
    transition_days => 30,
    glacier_days => 365,
);

# Constructeur
sub new {
    my ($class, $params) = @_;
    
    $params //= {};
    
    my $self = {
        config => { %DEFAULT_CONFIG },
        validated => 0,
    };
    
    bless $self, $class;
    
    # Application des paramètres fournis
    $self->_merge_config($params);
    
    # Validation de la configuration
    $self->validate();
    
    return $self;
}

# Fusion avec la configuration par défaut
sub _merge_config {
    my ($self, $params) = @_;
    
    foreach my $key (keys %$params) {
        if (defined $params->{$key}) {
            $self->{config}->{$key} = $params->{$key};
        }
    }
}

# Validation de la configuration
sub validate {
    my ($self) = @_;
    
    my $config = $self->{config};
    
    # Validation de l'endpoint
    if (!$config->{endpoint}) {
        die S3ConfigException("Endpoint is required", 'endpoint');
    }
    
    my $endpoint_info = parse_endpoint($config->{endpoint});
    if (!$endpoint_info) {
        die S3ConfigException("Invalid endpoint format: $config->{endpoint}", 'endpoint');
    }
    $self->{endpoint_info} = $endpoint_info;
    
    # Validation du bucket
    if (!$config->{bucket}) {
        die S3ConfigException("Bucket name is required", 'bucket');
    }
    
    if (!validate_bucket_name($config->{bucket})) {
        die S3ConfigException("Invalid bucket name: $config->{bucket}", 'bucket');
    }
    
    # Validation de la région
    if (!$config->{region} || $config->{region} !~ /^[a-z0-9-]+$/) {
        die S3ConfigException("Invalid region: $config->{region}", 'region');
    }
    
    # Validation des timeouts
    $self->_validate_timeout('connection_timeout', 10, 300);
    $self->_validate_timeout('read_timeout', 30, 3600);
    
    # Validation des paramètres de transfert
    $self->_validate_positive_integer('multipart_chunk_size', 5*1024*1024, 5*1024*1024*1024);
    $self->_validate_positive_integer('max_concurrent_uploads', 1, 20);
    $self->_validate_positive_integer('max_concurrent_downloads', 1, 20);
    $self->_validate_positive_integer('max_retries', 0, 10);
    
    # Validation de la classe de stockage
    my @valid_storage_classes = qw(
        STANDARD STANDARD_IA ONEZONE_IA REDUCED_REDUNDANCY
        GLACIER DEEP_ARCHIVE INTELLIGENT_TIERING
    );
    if (!grep { $_ eq $config->{storage_class} } @valid_storage_classes) {
        die S3ConfigException("Invalid storage class: $config->{storage_class}", 'storage_class');
    }
    
    # Validation du chiffrement
    if ($config->{server_side_encryption}) {
        my @valid_encryption = qw(AES256 aws:kms);
        if (!grep { $_ eq $config->{server_side_encryption} } @valid_encryption) {
            die S3ConfigException(
                "Invalid server-side encryption: $config->{server_side_encryption}", 
                'server_side_encryption'
            );
        }
        
        # Si KMS, vérification de la clé
        if ($config->{server_side_encryption} eq 'aws:kms' && !$config->{kms_key_id}) {
            log_warn("KMS encryption specified but no KMS key ID provided");
        }
    }
    
    # Validation du préfixe
    if ($config->{prefix}) {
        $config->{prefix} =~ s|/+$|/|;  # Normalise le slash final
        if ($config->{prefix} =~ /[^a-zA-Z0-9!_.*'()\/-]/) {
            log_warn("Prefix contains special characters that may cause issues: $config->{prefix}");
        }
    }
    
    # Validation du cycle de vie
    if ($config->{lifecycle_enabled}) {
        $self->_validate_positive_integer('transition_days', 1, 36500);
        $self->_validate_positive_integer('glacier_days', 1, 36500);
        
        if ($config->{glacier_days} <= $config->{transition_days}) {
            die S3ConfigException(
                "Glacier transition days must be greater than IA transition days",
                'glacier_days'
            );
        }
    }
    
    $self->{validated} = 1;
    log_info("S3 configuration validated successfully");
}

# Validation d'un timeout
sub _validate_timeout {
    my ($self, $key, $min, $max) = @_;
    
    my $value = $self->{config}->{$key};
    
    if (!defined $value || $value !~ /^\d+$/ || $value < $min || $value > $max) {
        die S3ConfigException(
            "Invalid $key: must be between $min and $max seconds", 
            $key
        );
    }
}

# Validation d'un entier positif avec bornes
sub _validate_positive_integer {
    my ($self, $key, $min, $max) = @_;
    
    my $value = $self->{config}->{$key};
    
    if (!defined $value || $value !~ /^\d+$/ || $value < $min || $value > $max) {
        die S3ConfigException(
            "Invalid $key: must be between $min and $max", 
            $key
        );
    }
}

# Accesseurs pour la configuration
sub get {
    my ($self, $key) = @_;
    
    return $self->{config}->{$key};
}

sub set {
    my ($self, $key, $value) = @_;
    
    $self->{config}->{$key} = $value;
    $self->{validated} = 0;  # Nécessite une re-validation
}

sub get_all {
    my ($self) = @_;
    
    return { %{$self->{config}} };  # Copie pour éviter les modifications
}

# Informations sur l'endpoint parsé
sub endpoint_info {
    my ($self) = @_;
    
    return $self->{endpoint_info};
}

# URL complète de l'endpoint
sub endpoint_url {
    my ($self) = @_;
    
    return $self->{endpoint_info}->{url};
}

# Host de l'endpoint
sub endpoint_host {
    my ($self) = @_;
    
    return $self->{endpoint_info}->{host};
}

# Utilise SSL?
sub use_ssl {
    my ($self) = @_;
    
    return $self->{endpoint_info}->{ssl} && $self->{config}->{use_ssl};
}

# Configuration des headers par défaut
sub default_headers {
    my ($self) = @_;
    
    my $headers = {
        'User-Agent' => 'Proxmox-S3-Plugin/1.0',
        'Host' => $self->endpoint_host(),
    };
    
    # Headers de chiffrement
    if ($self->{config}->{server_side_encryption}) {
        $headers->{'x-amz-server-side-encryption'} = $self->{config}->{server_side_encryption};
        
        if ($self->{config}->{kms_key_id}) {
            $headers->{'x-amz-server-side-encryption-aws-kms-key-id'} = $self->{config}->{kms_key_id};
        }
    }
    
    # Classe de stockage par défaut
    if ($self->{config}->{storage_class} ne 'STANDARD') {
        $headers->{'x-amz-storage-class'} = $self->{config}->{storage_class};
    }
    
    return $headers;
}

# Configuration pour les uploads multipart
sub multipart_config {
    my ($self) = @_;
    
    return {
        chunk_size => $self->{config}->{multipart_chunk_size},
        max_concurrent => $self->{config}->{max_concurrent_uploads},
        threshold => $self->{config}->{multipart_chunk_size},  # Utilise multipart si > chunk_size
    };
}

# Configuration du cycle de vie
sub lifecycle_config {
    my ($self) = @_;
    
    return undef if !$self->{config}->{lifecycle_enabled};
    
    return {
        enabled => 1,
        transition_days => $self->{config}->{transition_days},
        glacier_days => $self->{config}->{glacier_days},
        prefix => $self->{config}->{prefix},
    };
}

# Export de la configuration pour le logging
sub to_log_string {
    my ($self) = @_;
    
    my $config = $self->{config};
    my @parts = ();
    
    push @parts, "endpoint=$config->{endpoint}";
    push @parts, "bucket=$config->{bucket}";
    push @parts, "region=$config->{region}";
    push @parts, "prefix=$config->{prefix}";
    push @parts, "storage_class=$config->{storage_class}";
    push @parts, "ssl=" . ($self->use_ssl() ? 'yes' : 'no');
    
    if ($config->{server_side_encryption}) {
        push @parts, "encryption=$config->{server_side_encryption}";
    }
    
    return join(', ', @parts);
}

# Sérialisation pour le cache
sub serialize {
    my ($self) = @_;
    
    require JSON;
    return JSON::encode_json({
        config => $self->{config},
        endpoint_info => $self->{endpoint_info},
        validated => $self->{validated},
    });
}

# Désérialisation depuis le cache
sub deserialize {
    my ($class, $json_data) = @_;
    
    require JSON;
    my $data = JSON::decode_json($json_data);
    
    my $self = bless {
        config => $data->{config},
        endpoint_info => $data->{endpoint_info},
        validated => $data->{validated},
    }, $class;
    
    return $self;
}

# Vérification si la configuration a changé
sub has_changed {
    my ($self, $other_config) = @_;
    
    return 1 if !$other_config;
    
    my $current = $self->{config};
    
    # Comparaison des clés importantes
    my @important_keys = qw(
        endpoint bucket region prefix storage_class
        server_side_encryption kms_key_id
        multipart_chunk_size max_concurrent_uploads
    );
    
    foreach my $key (@important_keys) {
        my $current_val = $current->{$key} // '';
        my $other_val = $other_config->{$key} // '';
        
        return 1 if $current_val ne $other_val;
    }
    
    return 0;
}

# Validation de compatibilité avec une autre configuration
sub is_compatible_with {
    my ($self, $other_config) = @_;
    
    return 0 if !$other_config;
    
    my $current = $self->{config};
    
    # Les éléments suivants doivent être identiques
    my @required_same = qw(endpoint bucket region);
    
    foreach my $key (@required_same) {
        my $current_val = $current->{$key} // '';
        my $other_val = $other_config->{$key} // '';
        
        return 0 if $current_val ne $other_val;
    }
    
    return 1;
}

1;