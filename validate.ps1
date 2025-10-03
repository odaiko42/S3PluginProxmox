# Script de validation du Plugin S3 pour Proxmox VE (Windows)
# Ce script teste la syntaxe et la structure des modules Perl

param(
    [string]$SourcePath = ".",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

Write-Host "=== Validation du Plugin S3 Proxmox VE ===" -ForegroundColor Cyan

# Vérifier que Perl est disponible
try {
    $perlVersion = perl -v 2>$null | Select-String "version"
    Write-Host "✓ Perl détecté: $($perlVersion.Line.Trim())" -ForegroundColor Green
} catch {
    Write-Host "✗ Perl non trouvé. Installez Perl pour continuer." -ForegroundColor Red
    exit 1
}

# Chemins des fichiers
$sourceDir = Resolve-Path $SourcePath
$s3ClientPath = Join-Path $sourceDir "PVE\Storage\Custom\S3Client.pm"
$s3PluginPath = Join-Path $sourceDir "PVE\Storage\Custom\S3PluginFull.pm" 

# Vérifier l'existence des fichiers
$files = @{
    "S3Client.pm" = $s3ClientPath
    "S3PluginFull.pm" = $s3PluginPath
}

foreach ($file in $files.GetEnumerator()) {
    if (Test-Path $file.Value) {
        $lineCount = (Get-Content $file.Value | Measure-Object -Line).Lines
        Write-Host "✓ $($file.Key) trouvé ($lineCount lignes)" -ForegroundColor Green
    } else {
        Write-Host "✗ $($file.Key) non trouvé: $($file.Value)" -ForegroundColor Red
        exit 1
    }
}

# Test de syntaxe Perl
Write-Host "`nVérification de la syntaxe Perl..." -ForegroundColor Yellow

foreach ($file in $files.GetEnumerator()) {
    Write-Host "Test syntaxe $($file.Key)..." -NoNewline
    
    $syntaxCheck = perl -I"$sourceDir" -c "$($file.Value)" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host " ✓" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  $syntaxCheck" -ForegroundColor Gray
        }
    } else {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "Erreur de syntaxe:" -ForegroundColor Red
        Write-Host $syntaxCheck -ForegroundColor Red
        exit 1
    }
}

# Vérification des modules Perl requis
Write-Host "`nVérification des dépendances Perl..." -ForegroundColor Yellow

$requiredModules = @(
    "strict",
    "warnings", 
    "HTTP::Request",
    "LWP::UserAgent",
    "Digest::SHA",
    "MIME::Base64",
    "POSIX",
    "URI::Escape",
    "XML::LibXML",
    "File::Path",
    "File::Basename",
    "File::Temp"
)

$missingModules = @()

foreach ($module in $requiredModules) {
    $moduleCheck = perl -M"$module" -e "exit 0" 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ $module" -ForegroundColor Green
    } else {
        Write-Host "✗ $module manquant" -ForegroundColor Red
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Host "`nModules Perl manquants:" -ForegroundColor Yellow
    foreach ($module in $missingModules) {
        Write-Host "  - $module" -ForegroundColor Red
    }
    Write-Host "`nInstallez les modules manquants avec cpan ou votre gestionnaire de paquets" -ForegroundColor Yellow
}

# Test des scripts de test
Write-Host "`nVérification des scripts de test..." -ForegroundColor Yellow

$testScripts = @(
    "test_s3_client.pl",
    "test_s3_plugin.pl"
)

foreach ($script in $testScripts) {
    $scriptPath = Join-Path $sourceDir $script
    
    if (Test-Path $scriptPath) {
        Write-Host "Test syntaxe $script..." -NoNewline
        
        $syntaxCheck = perl -I"$sourceDir" -c "$scriptPath" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✓" -ForegroundColor Green
        } else {
            Write-Host " ✗" -ForegroundColor Red
            Write-Host "Erreur: $syntaxCheck" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ $script non trouvé" -ForegroundColor Red
    }
}

# Analyse du contenu des fichiers
Write-Host "`nAnalyse du contenu des modules..." -ForegroundColor Yellow

# Vérifier S3Client.pm
$s3ClientContent = Get-Content $s3ClientPath -Raw
$clientFeatures = @{
    "Constructor (new)" = $s3ClientContent -match "sub new"
    "AWS Signature" = $s3ClientContent -match "_sign_request"
    "List Objects" = $s3ClientContent -match "list_objects"
    "Put Object" = $s3ClientContent -match "put_object"
    "Get Object" = $s3ClientContent -match "get_object"
    "Delete Object" = $s3ClientContent -match "delete_object"
    "Test Connection" = $s3ClientContent -match "test_connection"
}

Write-Host "Fonctionnalités S3Client:" -ForegroundColor Cyan
foreach ($feature in $clientFeatures.GetEnumerator()) {
    $status = if ($feature.Value) { "✓" } else { "✗" }
    $color = if ($feature.Value) { "Green" } else { "Red" }
    Write-Host "  $status $($feature.Key)" -ForegroundColor $color
}

# Vérifier S3Plugin.pm
$s3PluginContent = Get-Content $s3PluginPath -Raw
$pluginFeatures = @{
    "Base Class" = $s3PluginContent -match "use base.*PVE::Storage::Plugin"
    "API Method" = $s3PluginContent -match "sub api"
    "Type Method" = $s3PluginContent -match "sub type"
    "Plugin Data" = $s3PluginContent -match "sub plugindata"
    "Properties" = $s3PluginContent -match "sub properties"
    "Options" = $s3PluginContent -match "sub options"
    "Status Method" = $s3PluginContent -match "sub status"
    "List Images" = $s3PluginContent -match "list_images"
    "Parse Name" = $s3PluginContent -match "parse_name"
    "Volume Size" = $s3PluginContent -match "volume_size_info"
}

Write-Host "`nFonctionnalités S3Plugin:" -ForegroundColor Cyan
foreach ($feature in $pluginFeatures.GetEnumerator()) {
    $status = if ($feature.Value) { "✓" } else { "✗" }
    $color = if ($feature.Value) { "Green" } else { "Red" }
    Write-Host "  $status $($feature.Key)" -ForegroundColor $color
}

# Statistiques des fichiers
Write-Host "`nStatistiques des fichiers:" -ForegroundColor Yellow

foreach ($file in $files.GetEnumerator()) {
    $content = Get-Content $file.Value -Raw
    $lineCount = (Get-Content $file.Value | Measure-Object -Line).Lines
    $charCount = $content.Length
    $wordCount = ($content -split '\s+').Count
    
    Write-Host "$($file.Key):" -ForegroundColor Cyan
    Write-Host "  - Lignes: $lineCount (limite: 600)" -ForegroundColor $(if ($lineCount -le 600) { "Green" } else { "Red" })
    Write-Host "  - Caractères: $charCount" -ForegroundColor Gray
    Write-Host "  - Mots: $wordCount" -ForegroundColor Gray
}

Write-Host "`n=== Validation terminée ===" -ForegroundColor Cyan

if ($missingModules.Count -eq 0) {
    Write-Host "✓ Tous les tests passent - Le plugin est prêt pour l'installation" -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠ Validation réussie mais des dépendances manquent" -ForegroundColor Yellow
    exit 1
}