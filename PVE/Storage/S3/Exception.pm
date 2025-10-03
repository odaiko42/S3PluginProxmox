package PVE::Storage::S3::Exception;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(
    S3Exception 
    S3ConnectionException
    S3AuthException 
    S3BucketException
    S3TransferException
    S3ConfigException
);

# Exception de base S3
package PVE::Storage::S3::Exception::Base {
    use overload '""' => 'as_string';
    
    sub new {
        my ($class, $message, $code, $details) = @_;
        
        my $self = {
            message => $message // 'Unknown S3 error',
            code => $code // 'S3_ERROR',
            details => $details // {},
            timestamp => time(),
            stack_trace => _get_stack_trace(),
        };
        
        return bless $self, $class;
    }
    
    sub message { return $_[0]->{message}; }
    sub code { return $_[0]->{code}; }
    sub details { return $_[0]->{details}; }
    sub timestamp { return $_[0]->{timestamp}; }
    sub stack_trace { return $_[0]->{stack_trace}; }
    
    sub as_string {
        my ($self) = @_;
        return sprintf('[%s] %s', $self->{code}, $self->{message});
    }
    
    sub _get_stack_trace {
        my @stack = ();
        my $i = 1;
        
        while (my ($package, $filename, $line, $subroutine) = caller($i)) {
            push @stack, {
                package => $package,
                filename => $filename,
                line => $line,
                subroutine => $subroutine,
            };
            $i++;
            last if $i > 10;  # Limite la profondeur
        }
        
        return \@stack;
    }
}

# Exception générique S3
package PVE::Storage::S3::Exception {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $details) = @_;
        return $class->SUPER::new($message, 'S3_ERROR', $details);
    }
}

# Exception de connexion S3
package PVE::Storage::S3::Exception::Connection {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $details) = @_;
        return $class->SUPER::new($message, 'S3_CONNECTION_ERROR', $details);
    }
}

# Exception d'authentification S3
package PVE::Storage::S3::Exception::Auth {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $details) = @_;
        return $class->SUPER::new($message, 'S3_AUTH_ERROR', $details);
    }
}

# Exception de bucket S3
package PVE::Storage::S3::Exception::Bucket {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $bucket_name, $details) = @_;
        $details //= {};
        $details->{bucket_name} = $bucket_name if $bucket_name;
        return $class->SUPER::new($message, 'S3_BUCKET_ERROR', $details);
    }
}

# Exception de transfert S3
package PVE::Storage::S3::Exception::Transfer {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $operation, $details) = @_;
        $details //= {};
        $details->{operation} = $operation if $operation;
        return $class->SUPER::new($message, 'S3_TRANSFER_ERROR', $details);
    }
}

# Exception de configuration S3
package PVE::Storage::S3::Exception::Config {
    use parent 'PVE::Storage::S3::Exception::Base';
    
    sub new {
        my ($class, $message, $config_key, $details) = @_;
        $details //= {};
        $details->{config_key} = $config_key if $config_key;
        return $class->SUPER::new($message, 'S3_CONFIG_ERROR', $details);
    }
}

# Fonctions d'aide pour créer des exceptions spécifiques
sub S3Exception {
    my ($message, $details) = @_;
    return PVE::Storage::S3::Exception->new($message, $details);
}

sub S3ConnectionException {
    my ($message, $details) = @_;
    return PVE::Storage::S3::Exception::Connection->new($message, $details);
}

sub S3AuthException {
    my ($message, $details) = @_;
    return PVE::Storage::S3::Exception::Auth->new($message, $details);
}

sub S3BucketException {
    my ($message, $bucket_name, $details) = @_;
    return PVE::Storage::S3::Exception::Bucket->new($message, $bucket_name, $details);
}

sub S3TransferException {
    my ($message, $operation, $details) = @_;
    return PVE::Storage::S3::Exception::Transfer->new($message, $operation, $details);
}

sub S3ConfigException {
    my ($message, $config_key, $details) = @_;
    return PVE::Storage::S3::Exception::Config->new($message, $config_key, $details);
}

# Gestion centralisée des exceptions HTTP
sub handle_http_error {
    my ($response, $operation) = @_;
    
    my $code = $response->code;
    my $message = $response->message;
    my $content = $response->content // '';
    
    my $details = {
        http_code => $code,
        http_message => $message,
        operation => $operation,
    };
    
    # Parse du XML d'erreur S3 si disponible
    if ($content && $content =~ /<Error>/) {
        my $error_info = _parse_s3_error_xml($content);
        if ($error_info) {
            $details->{s3_error_code} = $error_info->{Code};
            $details->{s3_error_message} = $error_info->{Message};
            $details->{s3_request_id} = $error_info->{RequestId};
        }
    }
    
    # Classification des erreurs selon le code HTTP
    if ($code == 400) {
        return S3Exception("Bad Request: $message", $details);
    } elsif ($code == 401) {
        return S3AuthException("Authentication failed: $message", $details);
    } elsif ($code == 403) {
        return S3AuthException("Access denied: $message", $details);
    } elsif ($code == 404) {
        my $error_msg = $details->{s3_error_code} || 'Resource not found';
        if ($error_msg =~ /NoSuchBucket/) {
            return S3BucketException("Bucket does not exist", undef, $details);
        } else {
            return S3Exception("Not found: $message", $details);
        }
    } elsif ($code >= 500) {
        return S3ConnectionException("Server error: $message", $details);
    } else {
        return S3Exception("HTTP error $code: $message", $details);
    }
}

# Parse du XML d'erreur S3
sub _parse_s3_error_xml {
    my ($xml) = @_;
    
    return undef if !$xml;
    
    my $error_info = {};
    
    if ($xml =~ /<Code>([^<]+)<\/Code>/) {
        $error_info->{Code} = $1;
    }
    if ($xml =~ /<Message>([^<]+)<\/Message>/) {
        $error_info->{Message} = $1;
    }
    if ($xml =~ /<RequestId>([^<]+)<\/RequestId>/) {
        $error_info->{RequestId} = $1;
    }
    if ($xml =~ /<BucketName>([^<]+)<\/BucketName>/) {
        $error_info->{BucketName} = $1;
    }
    if ($xml =~ /<Key>([^<]+)<\/Key>/) {
        $error_info->{Key} = $1;
    }
    
    return %$error_info ? $error_info : undef;
}

# Retry logic pour les opérations S3
sub with_retry {
    my ($operation, $max_attempts, $base_delay) = @_;
    
    $max_attempts //= 3;
    $base_delay //= 1;
    
    my $attempt = 0;
    my $last_exception;
    
    while ($attempt < $max_attempts) {
        $attempt++;
        
        eval {
            return $operation->();
        };
        
        if ($@) {
            $last_exception = $@;
            
            # Ne retry pas sur certaines erreurs
            if (ref($@) && $@->isa('PVE::Storage::S3::Exception::Auth')) {
                die $@;  # Erreur d'auth, pas de retry
            }
            if (ref($@) && $@->isa('PVE::Storage::S3::Exception::Config')) {
                die $@;  # Erreur de config, pas de retry
            }
            
            # Dernière tentative, on lance l'exception
            if ($attempt >= $max_attempts) {
                die $@;
            }
            
            # Calcul du délai avec backoff exponentiel
            my $delay = $base_delay * (2 ** ($attempt - 1));
            $delay += rand($delay * 0.1);  # Ajoute un peu de jitter
            
            PVE::Storage::S3::Utils::log_warn(
                "S3 operation failed (attempt $attempt/$max_attempts), retrying in ${delay}s: $@"
            );
            
            sleep($delay);
        }
    }
    
    # Ne devrait jamais arriver
    die $last_exception;
}

# Log des exceptions avec détails
sub log_exception {
    my ($exception, $context) = @_;
    
    my $message = ref($exception) ? $exception->as_string() : "$exception";
    
    if (ref($exception) && $exception->isa('PVE::Storage::S3::Exception::Base')) {
        my $details = $exception->details;
        my $log_msg = "S3 Exception in $context: $message";
        
        if ($details && %$details) {
            $log_msg .= " Details: " . join(', ', map { "$_=$details->{$_}" } keys %$details);
        }
        
        PVE::Storage::S3::Utils::log_error($log_msg);
        
        # Log de la stack trace en mode debug
        if ($ENV{PVE_S3_DEBUG}) {
            my $stack = $exception->stack_trace;
            foreach my $frame (@$stack) {
                PVE::Storage::S3::Utils::log_error(
                    "  at $frame->{subroutine} ($frame->{filename}:$frame->{line})"
                );
            }
        }
    } else {
        PVE::Storage::S3::Utils::log_error("Exception in $context: $message");
    }
}

1;