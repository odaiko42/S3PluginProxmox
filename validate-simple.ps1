# Script de validation simplifié pour le Plugin S3 Proxmox VE

param([string]$SourcePath = ".")

Write-Host "=== Validation du Plugin S3 Proxmox VE ===" -ForegroundColor Cyan

# Vérifier Perl
$perlTest = perl -e "print 'OK'" 2>$null
if ($perlTest -eq "OK") {
    Write-Host "[OK] Perl détecté" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Perl non trouvé" -ForegroundColor Red
    exit 1
}

# Chemins des fichiers
$sourceDir = Resolve-Path $SourcePath
$s3ClientPath = Join-Path $sourceDir "PVE\Storage\Custom\S3Client.pm"
$s3PluginPath = Join-Path $sourceDir "PVE\Storage\Custom\S3PluginFull.pm"

# Vérifier les fichiers
$files = @{
    "S3Client.pm" = $s3ClientPath
    "S3PluginFull.pm" = $s3PluginPath
}

Write-Host "`nVérification des fichiers:" -ForegroundColor Yellow

foreach ($file in $files.GetEnumerator()) {
    if (Test-Path $file.Value) {
        $lineCount = (Get-Content $file.Value | Measure-Object -Line).Lines
        Write-Host "[OK] $($file.Key) - $lineCount lignes" -ForegroundColor Green
    } else {
        Write-Host "[ERREUR] $($file.Key) manquant" -ForegroundColor Red
        exit 1
    }
}

# Test syntaxe Perl
Write-Host "`nTest de syntaxe Perl:" -ForegroundColor Yellow

foreach ($file in $files.GetEnumerator()) {
    Write-Host "Vérification $($file.Key)..." -NoNewline
    
    perl -I"$sourceDir" -c "$($file.Value)" >$null 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [OK]" -ForegroundColor Green
    } else {
        Write-Host " [ERREUR]" -ForegroundColor Red
        exit 1
    }
}

# Modules Perl requis
Write-Host "`nVérification des dépendances:" -ForegroundColor Yellow

$modules = @("HTTP::Request", "LWP::UserAgent", "XML::LibXML", "Digest::SHA")
$missing = @()

foreach ($module in $modules) {
    perl -M"$module" -e "exit 0" >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $module" -ForegroundColor Green
    } else {
        Write-Host "[MANQUANT] $module" -ForegroundColor Red
        $missing += $module
    }
}

# Analyse rapide du contenu
Write-Host "`nAnalyse du contenu:" -ForegroundColor Yellow

$s3ClientContent = Get-Content $s3ClientPath -Raw
$s3PluginContent = Get-Content $s3PluginPath -Raw

# Vérifications importantes
$checks = @{
    "S3Client::new" = $s3ClientContent -match "sub new"
    "S3Client::_sign_request" = $s3ClientContent -match "_sign_request"
    "S3Client::list_objects" = $s3ClientContent -match "list_objects"
    "S3Plugin::type" = $s3PluginContent -match "sub type"
    "S3Plugin::status" = $s3PluginContent -match "sub status"
    "S3Plugin::list_images" = $s3PluginContent -match "list_images"
}

foreach ($check in $checks.GetEnumerator()) {
    $status = if ($check.Value) { "[OK]" } else { "[MANQUANT]" }
    $color = if ($check.Value) { "Green" } else { "Red" }
    Write-Host "$status $($check.Key)" -ForegroundColor $color
}

Write-Host "`n=== Résumé ===" -ForegroundColor Cyan

if ($missing.Count -eq 0) {
    Write-Host "[OK] Plugin validé - Prêt pour l'installation" -ForegroundColor Green
} else {
    Write-Host "[ATTENTION] Modules manquants: $($missing -join ', ')" -ForegroundColor Yellow
}

Write-Host "`nPour installer:" -ForegroundColor White
Write-Host "  Linux: sudo ./install.sh" -ForegroundColor Gray
Write-Host "  Test: perl test_s3_client.pl" -ForegroundColor Gray