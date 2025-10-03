package PVE::Storage::S3::Metadata;

use strict;
use warnings;

use JSON;
use POSIX qw(strftime);
use File::Basename qw(basename);

use PVE::Storage::S3::Utils qw(log_info log_warn sanitize_metadata);

# Préfixes standard pour les métadonnées Proxmox
use constant {
    PVE_META_PREFIX => 'x-pve-',
    BACKUP_META_PREFIX => 'x-pve-backup-',
    VM_META_PREFIX => 'x-pve-vm-',
};

# Constructeur
sub new {
    my ($class, $initial_metadata) = @_;
    
    my $self = {
        metadata => {},
        system_metadata => {},
        user_metadata => {},
    };
    
    bless $self, $class;
    
    if ($initial_metadata) {
        $self->set_from_hash($initial_metadata);
    }
    
    return $self;
}

# Définition des métadonnées depuis un hash
sub set_from_hash {
    my ($self, $metadata_hash) = @_;
    
    return if !$metadata_hash || ref($metadata_hash) ne 'HASH';
    
    # Nettoyage et validation
    my $clean_metadata = sanitize_metadata($metadata_hash);
    
    # Classification des métadonnées
    foreach my $key (keys %$clean_metadata) {
        my $value = $clean_metadata->{$key};
        
        if ($key =~ /^x-pve-/) {
            $self->{system_metadata}->{$key} = $value;
        } else {
            $self->{user_metadata}->{$key} = $value;
        }
        
        $self->{metadata}->{$key} = $value;
    }
}

# Métadonnées pour un backup Proxmox
sub set_backup_metadata {
    my ($self, $params) = @_;
    
    $params //= {};
    
    # Métadonnées obligatoires pour un backup
    $self->_set_pve_meta('backup-type', $params->{type} || 'unknown');
    $self->_set_pve_meta('vmid', $params->{vmid}) if $params->{vmid};
    $self->_set_pve_meta('backup-time', $params->{backup_time} || time());
    $self->_set_pve_meta('backup-format', $params->{format}) if $params->{format};
    
    # Informations sur la compression
    if ($params->{compression}) {
        $self->_set_pve_meta('compression', $params->{compression});
    }
    
    # Taille originale vs compressée
    if (defined $params->{original_size}) {
        $self->_set_pve_meta('original-size', $params->{original_size});
    }
    if (defined $params->{compressed_size}) {
        $self->_set_pve_meta('compressed-size', $params->{compressed_size});
    }
    
    # Checksum du contenu
    if ($params->{checksum}) {
        $self->_set_pve_meta('checksum', $params->{checksum});
        $self->_set_pve_meta('checksum-algorithm', $params->{checksum_algorithm} || 'sha256');
    }
    
    # Informations de configuration
    if ($params->{config_data}) {
        # Stockage de la configuration en base64 si elle est compacte
        if (length($params->{config_data}) < 2048) {
            require MIME::Base64;
            my $encoded_config = MIME::Base64::encode_base64($params->{config_data}, '');
            $self->_set_pve_meta('config', $encoded_config);
        }
    }
    
    # Informations sur l'environnement de backup
    $self->_set_pve_meta('pve-version', $params->{pve_version}) if $params->{pve_version};
    $self->_set_pve_meta('hostname', $params->{hostname}) if $params->{hostname};
    $self->_set_pve_meta('node', $params->{node}) if $params->{node};
}

# Métadonnées pour une VM/CT
sub set_vm_metadata {
    my ($self, $params) = @_;
    
    $params //= {};
    
    # Informations de base
    $self->_set_pve_meta('vmid', $params->{vmid}) if $params->{vmid};
    $self->_set_pve_meta('vm-type', $params->{vm_type} || 'qemu');
    $self->_set_pve_meta('format', $params->{format}) if $params->{format};
    
    # Taille du disque
    if (defined $params->{size}) {
        $self->_set_pve_meta('size', $params->{size});
    }
    if (defined $params->{virtual_size}) {
        $self->_set_pve_meta('virtual-size', $params->{virtual_size});
    }
    
    # Informations sur le disque
    if ($params->{disk_type}) {
        $self->_set_pve_meta('disk-type', $params->{disk_type});
    }
    if ($params->{bus_type}) {
        $self->_set_pve_meta('bus-type', $params->{bus_type});
    }
    
    # Snapshot information
    if ($params->{snapshot}) {
        $self->_set_pve_meta('snapshot', $params->{snapshot});
        $self->_set_pve_meta('parent-image', $params->{parent_image}) if $params->{parent_image};
    }
}

# Métadonnées pour un fichier ISO/template
sub set_file_metadata {
    my ($self, $params) = @_;
    
    $params //= {};
    
    # Type de contenu
    $self->_set_pve_meta('content-type', $params->{content_type}) if $params->{content_type};
    
    # Informations sur le fichier original
    if ($params->{original_filename}) {
        $self->_set_pve_meta('original-filename', basename($params->{original_filename}));
    }
    
    # Checksum et validation
    if ($params->{md5sum}) {
        $self->_set_pve_meta('md5sum', $params->{md5sum});
    }
    if ($params->{sha256sum}) {
        $self->_set_pve_meta('sha256sum', $params->{sha256sum});
    }
    
    # Informations de provenance
    if ($params->{source_url}) {
        $self->_set_pve_meta('source-url', $params->{source_url});
    }
    if ($params->{downloaded_time}) {
        $self->_set_pve_meta('downloaded-time', $params->{downloaded_time});
    }
}

# Ajout d'une métadonnée personnalisée
sub set_custom_metadata {
    my ($self, $key, $value) = @_;
    
    return if !defined $key || !defined $value;
    
    # Nettoyage de la clé
    $key =~ s/[^a-zA-Z0-9_-]/_/g;
    $key = lc($key);
    
    # Limitation de la taille
    $value = substr($value, 0, 2048) if length($value) > 2048;
    
    $self->{user_metadata}->{$key} = $value;
    $self->{metadata}->{$key} = $value;
}

# Définition d'une métadonnée système PVE
sub _set_pve_meta {
    my ($self, $key, $value) = @_;
    
    return if !defined $key || !defined $value;
    
    my $meta_key = PVE_META_PREFIX . $key;
    $self->{system_metadata}->{$meta_key} = "$value";
    $self->{metadata}->{$meta_key} = "$value";
}

# Récupération d'une métadonnée
sub get {
    my ($self, $key) = @_;
    
    return $self->{metadata}->{$key};
}

# Récupération d'une métadonnée PVE
sub get_pve_meta {
    my ($self, $key) = @_;
    
    my $meta_key = PVE_META_PREFIX . $key;
    return $self->{metadata}->{$meta_key};
}

# Récupération de toutes les métadonnées
sub get_all {
    my ($self) = @_;
    
    return { %{$self->{metadata}} };
}

# Récupération des métadonnées système uniquement
sub get_system_metadata {
    my ($self) = @_;
    
    return { %{$self->{system_metadata}} };
}

# Récupération des métadonnées utilisateur uniquement
sub get_user_metadata {
    my ($self) = @_;
    
    return { %{$self->{user_metadata}} };
}

# Parse des métadonnées depuis un objet S3
sub parse_from_s3_object {
    my ($self, $s3_metadata) = @_;
    
    return if !$s3_metadata || ref($s3_metadata) ne 'HASH';
    
    foreach my $key (keys %$s3_metadata) {
        # Les métadonnées S3 ont un préfixe x-amz-meta- qui est supprimé
        my $clean_key = $key;
        $clean_key =~ s/^x-amz-meta-//i;
        
        if ($clean_key ne $key) {  # C'était bien une métadonnée utilisateur
            $self->set_custom_metadata($clean_key, $s3_metadata->{$key});
        }
    }
}

# Génération des headers HTTP pour S3
sub to_s3_headers {
    my ($self) = @_;
    
    my $headers = {};
    
    foreach my $key (keys %{$self->{metadata}}) {
        my $value = $self->{metadata}->{$key};
        
        # Les métadonnées personnalisées ont le préfixe x-amz-meta-
        my $header_key = "x-amz-meta-$key";
        
        # Validation de la valeur pour S3
        $value =~ s/[\x00-\x1f\x7f]//g;  # Supprime les caractères de contrôle
        $value = substr($value, 0, 2048);  # Limite AWS S3
        
        $headers->{$header_key} = $value;
    }
    
    return $headers;
}

# Export pour le logging et debug
sub to_log_string {
    my ($self) = @_;
    
    my @parts = ();
    
    # Métadonnées importantes pour les logs
    my @important_keys = qw(
        x-pve-vmid x-pve-backup-type x-pve-format 
        x-pve-size x-pve-backup-time x-pve-node
    );
    
    foreach my $key (@important_keys) {
        if (my $value = $self->get($key)) {
            $key =~ s/^x-pve-//;  # Simplifie pour les logs
            push @parts, "$key=$value";
        }
    }
    
    return join(', ', @parts);
}

# Sérialisation JSON pour le stockage
sub to_json {
    my ($self) = @_;
    
    return encode_json({
        metadata => $self->{metadata},
        timestamp => time(),
    });
}

# Désérialisation depuis JSON
sub from_json {
    my ($class, $json_data) = @_;
    
    my $data = decode_json($json_data);
    
    my $self = $class->new();
    $self->set_from_hash($data->{metadata});
    
    return $self;
}

# Fusion avec d'autres métadonnées
sub merge {
    my ($self, $other_metadata) = @_;
    
    if (ref($other_metadata) eq 'PVE::Storage::S3::Metadata') {
        $other_metadata = $other_metadata->get_all();
    }
    
    return if !$other_metadata || ref($other_metadata) ne 'HASH';
    
    foreach my $key (keys %$other_metadata) {
        # Ne remplace que si la valeur n'existe pas déjà
        if (!exists $self->{metadata}->{$key}) {
            $self->{metadata}->{$key} = $other_metadata->{$key};
            
            if ($key =~ /^x-pve-/) {
                $self->{system_metadata}->{$key} = $other_metadata->{$key};
            } else {
                $self->{user_metadata}->{$key} = $other_metadata->{$key};
            }
        }
    }
}

# Validation des métadonnées pour backup
sub validate_backup_metadata {
    my ($self) = @_;
    
    my @required = qw(x-pve-backup-type x-pve-backup-time);
    
    foreach my $required_meta (@required) {
        if (!$self->get($required_meta)) {
            return "Missing required backup metadata: $required_meta";
        }
    }
    
    # Validation du type de backup
    my $backup_type = $self->get_pve_meta('backup-type');
    if ($backup_type && $backup_type !~ /^(qemu|lxc|host)$/) {
        return "Invalid backup type: $backup_type";
    }
    
    # Validation du VMID si présent
    my $vmid = $self->get_pve_meta('vmid');
    if ($vmid && $vmid !~ /^\d+$/) {
        return "Invalid VMID format: $vmid";
    }
    
    return undef;  # Pas d'erreur
}

# Génération automatique des métadonnées de timestamp
sub set_timestamps {
    my ($self, $creation_time, $modification_time) = @_;
    
    $creation_time //= time();
    $modification_time //= $creation_time;
    
    $self->_set_pve_meta('created-time', $creation_time);
    $self->_set_pve_meta('modified-time', $modification_time);
    $self->_set_pve_meta('created-iso', strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($creation_time)));
}

# Mise à jour du timestamp de modification
sub touch {
    my ($self) = @_;
    
    my $now = time();
    $self->_set_pve_meta('modified-time', $now);
    $self->_set_pve_meta('modified-iso', strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($now)));
}

# Informations résumées pour l'interface
sub summary {
    my ($self) = @_;
    
    my $summary = {
        total_metadata_count => scalar(keys %{$self->{metadata}}),
        system_metadata_count => scalar(keys %{$self->{system_metadata}}),
        user_metadata_count => scalar(keys %{$self->{user_metadata}}),
    };
    
    # Ajout d'informations importantes si disponibles
    if (my $vmid = $self->get_pve_meta('vmid')) {
        $summary->{vmid} = $vmid;
    }
    if (my $backup_type = $self->get_pve_meta('backup-type')) {
        $summary->{backup_type} = $backup_type;
    }
    if (my $size = $self->get_pve_meta('size')) {
        $summary->{size} = $size;
    }
    
    return $summary;
}

1;