package PVE::Storage::S3::Transfer;

use strict;
use warnings;

use File::stat;
use File::Temp qw(tempfile);
use Time::HiRes qw(time sleep);
use POSIX qw(ceil);

use PVE::Storage::S3::Utils qw(log_info log_warn log_error generate_operation_id file_md5_hex);
use PVE::Storage::S3::Exception qw(S3TransferException with_retry);

# Constructeur
sub new {
    my ($class, $s3_client, $config) = @_;
    
    my $self = {
        s3_client => $s3_client,
        config => $config,
        active_transfers => {},
        transfer_stats => {},
    };
    
    bless $self, $class;
    
    return $self;
}

# Upload d'un fichier avec optimisations
sub upload_file {
    my ($self, $local_file, $bucket, $key, $options) = @_;
    
    $options //= {};
    
    # Validation du fichier local
    if (!-f $local_file) {
        die S3TransferException("Local file not found: $local_file", 'upload');
    }
    
    my $file_size = -s $local_file;
    my $multipart_config = $self->{config}->multipart_config();
    
    my $operation_id = generate_operation_id();
    log_info("Starting upload: $local_file -> s3://$bucket/$key (size: $file_size bytes, op: $operation_id)");
    
    eval {
        if ($file_size > $multipart_config->{threshold}) {
            return $self->_multipart_upload($local_file, $bucket, $key, $options, $operation_id);
        } else {
            return $self->_simple_upload($local_file, $bucket, $key, $options, $operation_id);
        }
    };
    if ($@) {
        $self->_cleanup_transfer($operation_id);
        die $@;
    }
}

# Download d'un fichier avec optimisations
sub download_file {
    my ($self, $bucket, $key, $local_file, $options) = @_;
    
    $options //= {};
    
    my $operation_id = generate_operation_id();
    log_info("Starting download: s3://$bucket/$key -> $local_file (op: $operation_id)");
    
    eval {
        # Récupération des informations sur l'objet
        my $object_info = $self->{s3_client}->head_object($bucket, $key);
        my $file_size = $object_info->{ContentLength} || 0;
        
        if ($file_size > 100 * 1024 * 1024) {  # > 100MB
            return $self->_multipart_download($bucket, $key, $local_file, $file_size, $options, $operation_id);
        } else {
            return $self->_simple_download($bucket, $key, $local_file, $options, $operation_id);
        }
    };
    if ($@) {
        $self->_cleanup_transfer($operation_id);
        die $@;
    }
}

# Upload simple pour petits fichiers
sub _simple_upload {
    my ($self, $local_file, $bucket, $key, $options, $operation_id) = @_;
    
    $self->_register_transfer($operation_id, 'upload', $local_file, { bucket => $bucket, key => $key });
    
    my $start_time = time();
    
    # Lecture du fichier
    open my $fh, '<:raw', $local_file or die S3TransferException("Cannot open file: $!", 'upload');
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Calcul du checksum
    my $md5_hex = file_md5_hex($local_file);
    
    # Préparation des headers
    my $headers = {
        'Content-Type' => $options->{content_type} || 'application/octet-stream',
        'Content-Length' => length($content),
        'Content-MD5' => _hex_to_base64($md5_hex),
    };
    
    # Ajout des métadonnées
    if ($options->{metadata}) {
        foreach my $meta_key (keys %{$options->{metadata}}) {
            $headers->{"x-amz-meta-$meta_key"} = $options->{metadata}->{$meta_key};
        }
    }
    
    # Upload avec retry
    my $result = with_retry(sub {
        $self->{s3_client}->put_object($bucket, $key, $content, $headers);
    });
    
    my $duration = time() - $start_time;
    my $throughput = length($content) / $duration / 1024 / 1024;  # MB/s
    
    log_info("Simple upload completed: $operation_id (${throughput:.2f} MB/s)");
    
    $self->_unregister_transfer($operation_id);
    
    return {
        operation_id => $operation_id,
        etag => $result->{ETag},
        size => length($content),
        duration => $duration,
        throughput => $throughput,
    };
}

# Upload multipart pour gros fichiers
sub _multipart_upload {
    my ($self, $local_file, $bucket, $key, $options, $operation_id) = @_;
    
    my $file_size = -s $local_file;
    my $multipart_config = $self->{config}->multipart_config();
    my $chunk_size = $multipart_config->{chunk_size};
    my $max_concurrent = $multipart_config->{max_concurrent};
    
    $self->_register_transfer($operation_id, 'multipart_upload', $local_file, { 
        bucket => $bucket, 
        key => $key, 
        total_size => $file_size 
    });
    
    my $start_time = time();
    my $total_parts = ceil($file_size / $chunk_size);
    
    log_info("Multipart upload: $total_parts parts, chunk size: " . ($chunk_size / 1024 / 1024) . "MB");
    
    # Initiation du multipart upload
    my $upload_id = $self->{s3_client}->initiate_multipart_upload($bucket, $key, $options);
    
    eval {
        # Upload des parts avec parallélisation limitée
        my @parts = ();
        my @active_uploads = ();
        
        open my $fh, '<:raw', $local_file or die "Cannot open file: $!";
        
        for my $part_number (1..$total_parts) {
            # Lecture du chunk
            my $chunk_data;
            my $bytes_read = read($fh, $chunk_data, $chunk_size);
            last if $bytes_read == 0;
            
            # Limitation de la concurrence
            while (@active_uploads >= $max_concurrent) {
                $self->_wait_for_upload_completion(\@active_uploads, \@parts);
            }
            
            # Démarrage de l'upload de la part
            push @active_uploads, {
                part_number => $part_number,
                data => $chunk_data,
                size => $bytes_read,
                start_time => time(),
            };
            
            $self->_start_part_upload(\@active_uploads, $bucket, $key, $upload_id, $operation_id);
        }
        
        close $fh;
        
        # Attendre la fin de tous les uploads
        while (@active_uploads > 0) {
            $self->_wait_for_upload_completion(\@active_uploads, \@parts);
        }
        
        # Finalisation du multipart upload
        @parts = sort { $a->{PartNumber} <=> $b->{PartNumber} } @parts;
        my $result = $self->{s3_client}->complete_multipart_upload($bucket, $key, $upload_id, \@parts);
        
        my $duration = time() - $start_time;
        my $throughput = $file_size / $duration / 1024 / 1024;  # MB/s
        
        log_info("Multipart upload completed: $operation_id (${throughput:.2f} MB/s)");
        
        $self->_unregister_transfer($operation_id);
        
        return {
            operation_id => $operation_id,
            upload_id => $upload_id,
            etag => $result->{ETag},
            size => $file_size,
            parts_count => scalar(@parts),
            duration => $duration,
            throughput => $throughput,
        };
        
    };
    if ($@) {
        # Nettoyage en cas d'erreur
        eval {
            $self->{s3_client}->abort_multipart_upload($bucket, $key, $upload_id);
        };
        die S3TransferException("Multipart upload failed: $@", 'upload');
    }
}

# Démarrage de l'upload d'une part (simulation - en réalité serait asynchrone)
sub _start_part_upload {
    my ($self, $active_uploads, $bucket, $key, $upload_id, $operation_id) = @_;
    
    # Dans une vraie implémentation, ceci serait asynchrone
    my $upload = $active_uploads->[-1];
    
    eval {
        my $etag = $self->{s3_client}->upload_part(
            $bucket, $key, $upload_id, 
            $upload->{part_number}, 
            $upload->{data}
        );
        
        $upload->{etag} = $etag;
        $upload->{completed} = 1;
        $upload->{end_time} = time();
        
        # Mise à jour des statistiques de transfert
        $self->_update_transfer_progress($operation_id, $upload->{size});
        
    };
    if ($@) {
        $upload->{error} = $@;
        $upload->{completed} = 1;
    }
}

# Attente de la fin d'un upload et nettoyage
sub _wait_for_upload_completion {
    my ($self, $active_uploads, $completed_parts) = @_;
    
    # Vérifie les uploads terminés
    my @still_active = ();
    
    foreach my $upload (@$active_uploads) {
        if ($upload->{completed}) {
            if ($upload->{error}) {
                die S3TransferException("Part upload failed: $upload->{error}", 'upload');
            } else {
                push @$completed_parts, {
                    PartNumber => $upload->{part_number},
                    ETag => $upload->{etag},
                };
                
                my $duration = $upload->{end_time} - $upload->{start_time};
                my $throughput = $upload->{size} / $duration / 1024 / 1024;
                log_info("Part $upload->{part_number} completed (${throughput:.2f} MB/s)");
            }
        } else {
            push @still_active, $upload;
        }
    }
    
    @$active_uploads = @still_active;
    
    # Petit délai pour éviter une boucle trop intense
    sleep(0.1) if @still_active > 0;
}

# Download simple
sub _simple_download {
    my ($self, $bucket, $key, $local_file, $options, $operation_id) = @_;
    
    $self->_register_transfer($operation_id, 'download', $local_file, { bucket => $bucket, key => $key });
    
    my $start_time = time();
    
    my $result = with_retry(sub {
        $self->{s3_client}->get_object($bucket, $key, $local_file);
    });
    
    my $file_size = -s $local_file;
    my $duration = time() - $start_time;
    my $throughput = $file_size / $duration / 1024 / 1024;
    
    log_info("Simple download completed: $operation_id (${throughput:.2f} MB/s)");
    
    $self->_unregister_transfer($operation_id);
    
    return {
        operation_id => $operation_id,
        size => $file_size,
        duration => $duration,
        throughput => $throughput,
    };
}

# Download multipart (par ranges)
sub _multipart_download {
    my ($self, $bucket, $key, $local_file, $file_size, $options, $operation_id) = @_;
    
    my $chunk_size = 50 * 1024 * 1024;  # 50MB par chunk
    my $total_parts = ceil($file_size / $chunk_size);
    
    $self->_register_transfer($operation_id, 'multipart_download', $local_file, {
        bucket => $bucket,
        key => $key,
        total_size => $file_size,
    });
    
    log_info("Multipart download: $total_parts parts, chunk size: " . ($chunk_size / 1024 / 1024) . "MB");
    
    my $start_time = time();
    
    # Création du fichier de destination
    open my $output_fh, '>:raw', $local_file or die "Cannot create output file: $!";
    
    eval {
        for my $part_number (1..$total_parts) {
            my $range_start = ($part_number - 1) * $chunk_size;
            my $range_end = $range_start + $chunk_size - 1;
            $range_end = $file_size - 1 if $range_end >= $file_size;
            
            # Download de la range
            my $chunk_data = $self->{s3_client}->get_object_range(
                $bucket, $key, $range_start, $range_end
            );
            
            # Écriture dans le fichier
            print $output_fh $chunk_data;
            
            # Mise à jour du progrès
            $self->_update_transfer_progress($operation_id, length($chunk_data));
            
            log_info("Downloaded part $part_number/$total_parts");
        }
        
        close $output_fh;
        
        my $duration = time() - $start_time;
        my $throughput = $file_size / $duration / 1024 / 1024;
        
        log_info("Multipart download completed: $operation_id (${throughput:.2f} MB/s)");
        
        $self->_unregister_transfer($operation_id);
        
        return {
            operation_id => $operation_id,
            size => $file_size,
            parts_count => $total_parts,
            duration => $duration,
            throughput => $throughput,
        };
        
    };
    if ($@) {
        close $output_fh;
        unlink $local_file;  # Nettoyage du fichier incomplet
        die S3TransferException("Multipart download failed: $@", 'download');
    }
}

# Enregistrement d'un transfert actif
sub _register_transfer {
    my ($self, $operation_id, $type, $local_file, $remote_info) = @_;
    
    $self->{active_transfers}->{$operation_id} = {
        type => $type,
        local_file => $local_file,
        remote_info => $remote_info,
        start_time => time(),
        bytes_transferred => 0,
        status => 'active',
    };
    
    $self->{transfer_stats}->{$operation_id} = {
        start_time => time(),
        bytes_transferred => 0,
        last_update => time(),
    };
}

# Désenregistrement d'un transfert
sub _unregister_transfer {
    my ($self, $operation_id) = @_;
    
    if (my $transfer = $self->{active_transfers}->{$operation_id}) {
        $transfer->{status} = 'completed';
        $transfer->{end_time} = time();
    }
    
    # Nettoyage des statistiques anciennes (garde les infos pour debug)
    # delete $self->{transfer_stats}->{$operation_id};
}

# Nettoyage d'un transfert en cas d'erreur
sub _cleanup_transfer {
    my ($self, $operation_id) = @_;
    
    if (my $transfer = $self->{active_transfers}->{$operation_id}) {
        $transfer->{status} = 'failed';
        $transfer->{end_time} = time();
    }
}

# Mise à jour du progrès d'un transfert
sub _update_transfer_progress {
    my ($self, $operation_id, $bytes_transferred) = @_;
    
    my $stats = $self->{transfer_stats}->{$operation_id};
    return if !$stats;
    
    $stats->{bytes_transferred} += $bytes_transferred;
    $stats->{last_update} = time();
    
    # Log du progrès si transfer important
    my $transfer = $self->{active_transfers}->{$operation_id};
    if ($transfer && $transfer->{remote_info}->{total_size}) {
        my $progress = ($stats->{bytes_transferred} / $transfer->{remote_info}->{total_size}) * 100;
        if (int($progress) % 10 == 0) {  # Log tous les 10%
            log_info("Transfer progress: $operation_id - ${progress:.1f}%");
        }
    }
}

# Conversion MD5 hex vers base64 pour S3
sub _hex_to_base64 {
    my ($hex_string) = @_;
    
    require MIME::Base64;
    my $binary = pack('H*', $hex_string);
    return MIME::Base64::encode_base64($binary, '');
}

# Statistiques des transferts actifs
sub get_active_transfers {
    my ($self) = @_;
    
    my @active = ();
    foreach my $op_id (keys %{$self->{active_transfers}}) {
        my $transfer = $self->{active_transfers}->{$op_id};
        next if $transfer->{status} ne 'active';
        
        my $stats = $self->{transfer_stats}->{$op_id};
        
        push @active, {
            operation_id => $op_id,
            type => $transfer->{type},
            local_file => $transfer->{local_file},
            bytes_transferred => $stats->{bytes_transferred},
            duration => time() - $transfer->{start_time},
            remote_info => $transfer->{remote_info},
        };
    }
    
    return \@active;
}

# Annulation d'un transfert (si supporté)
sub cancel_transfer {
    my ($self, $operation_id) = @_;
    
    my $transfer = $self->{active_transfers}->{$operation_id};
    return 0 if !$transfer || $transfer->{status} ne 'active';
    
    $transfer->{status} = 'cancelled';
    $transfer->{end_time} = time();
    
    log_info("Transfer cancelled: $operation_id");
    return 1;
}

1;