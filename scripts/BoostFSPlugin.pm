package PVE::Storage::Custom::BoostFSPlugin;

use v5.34; # strict + warnings
use Cwd qw();
use File::Path qw(make_path);
use File::Basename qw(dirname);
use IO::File;
use POSIX qw(:errno_h);
use Time::HiRes qw(gettimeofday);

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

# BoostFS binary path
use constant BOOSTFS_BIN => '/opt/emc/boostfs/bin/boostfs';

# Plugin Definition
sub api { return 12; }
sub type { return 'boostfs'; }

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
        'sensitive-properties' => {},
        default_options => { compress => 0 },  # compression disabled
    };
}

sub properties {
    return {
        repo => {
           description => "BoostFS export (e.g., ddve01:/backup)",
           type => 'string',
           pattern => '^[^:]+:.+$',   # must look like server:/path 
        },
        fstype => {
            description => "File system type (default: boostfs)",
            type        => 'string',
            default     => 'boostfs',
        },
        boost_mkdir => {
            description => "Create directory if it doesn't exist",
            type        => 'boolean',
            default     => 1,
        },
        max_backups => {
            description => "Maximum number of backups to keep per VM",
            type        => 'integer',
            default     => 5,
        },
        compress => {
            description => "Compression setting (disabled for BoostFS)",
            type        => 'string',
            default     => '0',
        },
        'node-subdirs' => {
            description => "Create node-specific subdirectories in the repository",
            type        => 'boolean',
            default     => 0,
        },
        'timestamp-dirs' => {
            description => "Create timestamp-based subdirectories (YYYY-MM-DD/node/backup)",
            type        => 'boolean',
            default     => 0,
        },
    };
}

sub options {
    return {
        disable             => { optional => 1 },
        path                => { fixed    => 1 },
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

        # BoostFS Options
        repo           => {},
        fstype         => { optional => 1 },
        boost_mkdir    => { optional => 1 },
        max_backups    => { optional => 1 },
        compress       => { optional => 1 },  # Fixed: should be optional
        'node-subdirs' => { optional => 1 },  # Fixed: should be optional
        'timestamp-dirs' => { optional => 1 }, # Fixed: should be optional
    };
}

# -----------------------------
# BoostFS Helpers
# -----------------------------

sub boostfs_remote_from_config {
    my ($scfg) = @_;
    return $scfg->{repo};
}

sub create_boostfs_subdirs {
    my ($scfg) = @_;
    my $mountpoint = $scfg->{path};
    
    # Create timestamp-based subdirectory if enabled
    if ($scfg->{'timestamp-dirs'} // 0) {
        my ($seconds, $microseconds) = gettimeofday();
        my $timestamp = POSIX::strftime("%Y-%m-%d-%H-%M-%S", localtime($seconds));
        my $milliseconds = int($microseconds / 1000);
        $timestamp .= sprintf("-%03d", $milliseconds);
        
        my $timestamp_dir = "$mountpoint/$timestamp";
        make_path($timestamp_dir, { mode => 0755 }) if !-d $timestamp_dir;
        $mountpoint = $timestamp_dir;
    }
    
    # Create node-specific subdirectory if enabled
    if ($scfg->{'node-subdirs'} // 0) {
        my $node = PVE::INotify::nodename();
        my $node_dir = "$mountpoint/$node";
        make_path($node_dir, { mode => 0755 }) if !-d $node_dir;
    }
    
    # Create content-specific directories
    my @content_dirs = qw(images template/iso dump template/cache snippets);
    for my $dir (@content_dirs) {
        my $full_path = "$mountpoint/$dir";
        make_path($full_path, { mode => 0755 }) if !-d $full_path;
    }
}

sub boostfs_is_mounted {
    my ($scfg) = @_;
    my $mountpoint = Cwd::realpath($scfg->{path});
    return 0 if !defined($mountpoint);

    my $mountdata = PVE::ProcFSTools::parse_proc_mounts();

    # Check if the mountpoint is mounted and filesystem type is boostfs
    my $is_mounted = 0;
    for my $mount (@$mountdata) {
        my ($device, $mount_path, $fstype) = @$mount;
        if ($mount_path eq $mountpoint && $fstype eq 'fuse.boostfs') {
            $is_mounted = 1;
            last;
        }
    }

    return $is_mounted;
}

sub boostfs_mount {
    my ($scfg, $storeid) = @_;
    my $remote = boostfs_remote_from_config($scfg);
    my $mountpoint = $scfg->{path};

    # Check if mountpoint is already in use by a different filesystem
    my $mountdata = PVE::ProcFSTools::parse_proc_mounts();
    for my $mount (@$mountdata) {
        my ($device, $mount_path, $fstype) = @$mount;
        if ($mount_path eq $mountpoint && $fstype ne 'fuse.boostfs') {
            die "unable to mount BoostFS storage '$storeid' - mountpoint '$mountpoint' is already mounted with filesystem type '$fstype'\n";
        }
    }

    my $cmd = ['mount', '-t', 'boostfs', $remote, $mountpoint];

    eval {
        run_command(
            $cmd,
            timeout => 30,
            errfunc => sub { warn "$_[0]\n"; },
        );
    };
    if (my $err = $@) {
        die "failed to mount BoostFS storage '$remote' at '$mountpoint': $@\n";
    }

    die "BoostFS storage '$remote' not mounted at '$mountpoint' despite reported success\n"
        if !boostfs_is_mounted($scfg);

    return;
}

sub boostfs_umount {
    my ($scfg) = @_;
    my $mountpoint = $scfg->{path};
    my $cmd = ['umount', $mountpoint];

    eval {
        run_command(
            $cmd,
            timeout => 30,
            errfunc => sub { warn "$_[0]\n"; },
        );
    };
    if (my $err = $@) {
        die "failed to unmount BoostFS at '$mountpoint': $err\n";
    }

    return;
}

# -----------------------------
# Backup Management
# -----------------------------

# --- Support des backups avec gestion améliorée
sub list_backups {
    my ($class, $storeid, $scfg, $vmid, $vollist, $cache) = @_;
    
    my $path = $scfg->{path};
    my @backups = ();
    
    opendir(my $dh, $path) or die "Cannot open directory '$path': $!\n";
    
    while (my $file = readdir($dh)) {
        # Pattern pour les fichiers de backup Proxmox - Fixed regex
        if ($file =~ /^vzdump-(qemu|lxc)-(\d+)-(\d{4})_(\d{2})_(\d{2})-(\d{2})_(\d{2})_(\d{2})\.(vma\.zst|vma\.gz|vma|tar\.zst|tar\.gz|tar)$/) {
            my ($type, $backup_vmid, $year, $mon, $day, $hour, $min, $sec, $format) = 
               ($1, $2, $3, $4, $5, $6, $7, $8, $9);
            
            next if $vmid && $vmid != $backup_vmid;
            
            my $fullpath = "$path/$file";
            my $stat = stat($fullpath);
            
            push @backups, {
                volid => "$storeid:backup/$file",
                format => $format,
                size => $stat ? $stat->size : 0,
                vmid => $backup_vmid,
                ctime => $stat ? $stat->ctime : 0,
                type => $type,
            };
        }
    }
    
    closedir($dh);
    return \@backups;
}

# --- Suppression d'un backup
sub free_backup {
    my ($class, $storeid, $scfg, $volname) = @_;
    
    # Le volname pour les backups contient le préfixe 'backup/'
    $volname =~ s|^backup/||;
    
    my $fullpath = $scfg->{path} . "/" . $volname;
    
    if (-e $fullpath) {
        unlink $fullpath or die "Failed to remove backup '$fullpath': $!\n";
    }
    
    return undef;
}

# --- Backups Rotation
sub prune_backup {
    my ($class, $storeid, $scfg, $backups, $retention, $logfunc) = @_;

    # Fallback chain for retention count
    my $keep_count;
    
    if (ref($retention) eq 'HASH') {
        # Retention is a hash reference with policy settings
        $keep_count = $retention->{'keep-last'}           # Primary: from retention policy
                   // $retention->{'keep-daily'}          # Fallback: daily retention
                   // $retention->{'keep-weekly'}         # Fallback: weekly retention
                   // $retention->{'keep-monthly'}        # Fallback: monthly retention
                   // $retention->{'keep-yearly'};        # Fallback: yearly retention
    } elsif (defined($retention) && $retention =~ /^\d+$/) {
        # Retention is a simple number
        $keep_count = $retention;
    } else {
        # Retention is undefined or invalid
        $keep_count = undef;
    }
    
    # Additional fallback chain
    $keep_count = $keep_count
               // $scfg->{max_backups}                    # From storage configuration
               // 5;                                      # Default fallback
    
    # Log the retention policy being used
    $logfunc->("Using retention policy: keep $keep_count backups") if $logfunc;
    $logfunc->("Found " . scalar(@$backups) . " total backups") if $logfunc;

    # Sort backup files by their creation date (oldest first)
    my @ordered = sort { $a->{ctime} <=> $b->{ctime} } @$backups;

    # Determine which backups to prune
    my $excess = @$backups - $keep_count;
    
    if ($excess > 0) {
        $logfunc->("Need to remove $excess excess backups") if $logfunc;
        
        for my $backup (@ordered[0 .. $excess-1]) {
            my $path = $backup->{path};
            my $volid = $backup->{volid} // basename($path);
            
            if (unlink($path)) {
                $logfunc->("Pruned backup: $volid") if $logfunc;
            } else {
                $logfunc->("Failed to delete backup: $volid - $!") if $logfunc;
            }
        }
        
        $logfunc->("Backup pruning completed: removed $excess backups") if $logfunc;
    } else {
        $logfunc->("No backups need pruning (have " . scalar(@$backups) . ", keeping $keep_count)") if $logfunc;
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
    eval { boostfs_umount($scfg) if boostfs_is_mounted($scfg); };
    warn $@ if $@;
    return undef;
}

sub check_connection {
    my ($class, $storeid, $scfg, $cache) = @_;  # Added $cache parameter
    my $repo = $scfg->{repo};
    
    # Simply check if the mount exists and is accessible
    if (boostfs_is_mounted($scfg)) {
        return 1;
    }
    
    # Try to verify the remote is accessible without actually mounting
    # This is a simplified check - adjust based on actual BoostFS capabilities
    my ($server, $path) = split(':', $repo, 2);
    
    # Basic connectivity check
    my $cmd = ['ping', '-c', '1', '-W', '2', $server];
    eval {
        run_command($cmd, timeout => 5, outfunc => sub {}, errfunc => sub {});
    };
    
    return $@ ? 0 : 1;
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    my $mountpoint = $scfg->{path};

    # Check if already mounted as BoostFS
    if (!boostfs_is_mounted($scfg)) {
        # Create mount point directory if needed
        if ($scfg->{'create-base-path'} // 1) {
            make_path($mountpoint);
        }
        die "unable to activate storage '$storeid' - directory '$mountpoint' does not exist\n"
            if !-d $mountpoint;

        # Attempt to mount the BoostFS filesystem
        boostfs_mount($scfg, $storeid);
        
        # Verify mount was successful
        die "unable to activate storage '$storeid' - mount failed\n"
            if !boostfs_is_mounted($scfg);
        
        # Create subdirectories after successful mount
        create_boostfs_subdirs($scfg);
    } else {
        # Already mounted, just ensure subdirectories exist
        create_boostfs_subdirs($scfg);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
    return;
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;
    eval { boostfs_umount($scfg) if boostfs_is_mounted($scfg); };
    warn $@ if $@;
    return;
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;
    return undef if !boostfs_is_mounted($scfg);
    return $class->SUPER::status($storeid, $scfg, $cache);
}

sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;  # Fixed parameters
    my $path = $scfg->{path};
    
    # Apply timestamp and node subdirectories if enabled
    if ($scfg->{'timestamp-dirs'} // 0) {
        # Find the most recent timestamp directory
        opendir(my $dh, $path) or return $path;
        my @timestamp_dirs = sort grep { /^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-\d{3}$/ } readdir($dh);
        closedir($dh);
        if (@timestamp_dirs) {
            $path = "$path/$timestamp_dirs[-1]";  # Use the latest timestamp
        }
    }
    
    if ($scfg->{'node-subdirs'} // 0) {
        my $node = PVE::INotify::nodename();
        $path = "$path/$node";
    }
    
    # Add content-specific subdirectory based on volume type
    if (defined($volname)) {
        my ($vtype) = $class->parse_volname($volname);
        if ($vtype eq 'images') {
            $path = "$path/images";
        } elsif ($vtype eq 'iso') {
            $path = "$path/template/iso";
        } elsif ($vtype eq 'backup') {
            $path = "$path/dump";
        } elsif ($vtype eq 'vztmpl') {
            $path = "$path/template/cache";
        } elsif ($vtype eq 'snippets') {
            $path = "$path/snippets";
        }
        
        # Add volume filename to path if not just getting directory
        if ($volname !~ /\/$/) {
            my (undef, $name) = $class->parse_volname($volname);
            $path = "$path/$name" if $name;
        }
    }
    
    return wantarray ? ($path, undef, undef) : $path;  # Fixed return
}

sub volume_list {
    my ($class, $storeid, $scfg, $vmid, $content_types) = @_;
    my ($path) = $class->path($scfg);  # Fixed: get path correctly
    my @volumes = ();
    return \@volumes unless -d $path;

    # Use enhanced backup listing if content_types includes backup
    if ($content_types && grep { $_ eq 'backup' } @$content_types) {
        my $backups = $class->list_backups($storeid, $scfg, $vmid, undef, undef);
        push @volumes, @$backups;
    }

    # Handle other content types
    opendir(my $dh, $path) or return \@volumes;
    while (my $file = readdir($dh)) {
        next if $file =~ /^\.\.?$/;
        next unless -f "$path/$file";
        
        # Skip backup files if we already handled them above
        next if $file =~ /^vzdump-(qemu|lxc)-\d+-\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}\.(vma\.zst|vma\.gz|vma|tar\.zst|tar\.gz|tar)$/;
        
        # Handle other file types
        if ($file =~ /\.(vma|tar|vzdump)\.(gz|lzo|zst)?$/) {
            push @volumes, {
                volid  => "$storeid:$file",
                format => 'raw',
                size   => -s "$path/$file",
                ctime  => (stat("$path/$file"))[9],
            };
        }
    }
    closedir($dh);
    return \@volumes;
}

sub volume_size {
    my ($class, $storeid, $scfg, $volname) = @_;
    my ($path) = $class->path($scfg, $volname);  # Fixed: get path correctly
    return -s $path if -f $path;
    return 0;
}

sub free_storage {
    my ($class, $storeid, $scfg, $volname) = @_;
    
    # Check if this is a backup volume
    if ($volname =~ /^backup\//) {
        return $class->free_backup($storeid, $scfg, $volname);
    }
    
    # Handle other volume types
    my ($path) = $class->path($scfg, $volname);  # Fixed: get path correctly
    
    if (-f $path) {
        unlink $path or die "Failed to remove volume '$path': $!\n";
    }
    
    return undef;
}

sub parse_name {
    my ($class, $volname) = @_;
    return { volname => $volname };
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

sub get_volume_attribute {
    my ($class, $scfg, $storeid, $volname, $attribute) = @_;
    my ($vtype) = $class->parse_volname($volname);
    return if $vtype ne 'backup';

    my ($volume_path) = $class->path($scfg, $volname);  # Fixed: get path correctly

    if ($attribute eq 'notes') {
        my $notes_path = $volume_path . $class->SUPER::NOTES_EXT;
        if (-f $notes_path) {
            my $notes = file_get_contents($notes_path);
            return eval { decode('UTF-8', $notes, 1) } // $notes;
        }
        return "";
    }

    if ($attribute eq 'protected') {
        return -e PVE::Storage::protection_file_path($volume_path) ? 1 : 0;
    }

    return;
}

sub update_volume_attribute {
    my ($class, $scfg, $storeid, $volname, $attribute, $value) = @_;
    my ($vtype, $name) = $class->parse_volname($volname);
    die "only backups support attribute '$attribute'\n" if $vtype ne 'backup';

    my ($volume_path) = $class->path($scfg, $volname);  # Fixed: get path correctly

    if ($attribute eq 'notes') {
        my $notes_path = $volume_path . $class->SUPER::NOTES_EXT;
        if (defined($value)) {
            my $encoded_notes = encode('UTF-8', $value);
            file_set_contents($notes_path, $encoded_notes);
        } else {
            if (!unlink $notes_path) {
                return if $! == ENOENT;
                die "could not delete notes - $!\n";
            }
        }
        return;
    }

    if ($attribute eq 'protected') {
        my $protection_path = PVE::Storage::protection_file_path($volume_path);
        return if !((-e $protection_path) xor $value);
        if ($value) {
            my $fh = IO::File->new($protection_path, O_CREAT)
                or die "unable to create protection file '$protection_path' - $!\n";
            close($fh);
        } else {
            if (!unlink $protection_path) {
                return if $! == ENOENT;
                die "could not delete protection file '$protection_path' - $!\n";
            }
        }
        return;
    }

    die "attribute '$attribute' is not supported for storage type '$scfg->{type}'\n";
}

sub get_import_metadata {
    my ($class, $scfg, $storeid, $volname) = @_;
    return PVE::Storage::DirPlugin::get_import_metadata($class, $scfg, $storeid, $volname);
}

sub volume_qemu_snapshot_method {
    my ($class, $scfg, $storeid, $volname) = @_;
    return PVE::Storage::DirPlugin::volume_qemu_snapshot_method($class, $scfg, $storeid, $volname);
}

1;
