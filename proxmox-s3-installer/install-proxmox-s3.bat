@echo off
REM Script de lancement pour l'installateur Proxmox S3
REM Usage: install-proxmox-s3.bat <IP_PROXMOX> <USERNAME>

setlocal

if "%~2"=="" (
    echo Usage: %0 ^<IP_PROXMOX^> ^<USERNAME^>
    echo.
    echo Exemples:
    echo   %0 192.168.1.100 root
    echo   %0 10.0.0.50 admin
    echo.
    echo Options disponibles:
    echo   --dry-run    Afficher un aperçu sans faire de modifications
    echo.
    exit /b 1
)

set PROXMOX_IP=%1
set USERNAME=%2
set DRY_RUN=%3

echo ========================================
echo   INSTALLATEUR PROXMOX S3 STORAGE
echo ========================================
echo.
echo Serveur Proxmox: %PROXMOX_IP%
echo Utilisateur: %USERNAME%
echo.

if "%DRY_RUN%"=="--dry-run" (
    echo [MODE APERCU] Aucune modification ne sera apportee
    echo.
    python src\main.py %PROXMOX_IP% %USERNAME% --dry-run
) else (
    echo Lancement de l'installation...
    echo.
    python src\main.py %PROXMOX_IP% %USERNAME%
)

if %errorlevel% neq 0 (
    echo.
    echo ERREUR: L'installation a echoue (code %errorlevel%)
    echo Verifiez les logs ci-dessus pour plus de details.
    pause
    exit /b %errorlevel%
)

echo.
echo ========================================
echo   INSTALLATION TERMINEE AVEC SUCCES
echo ========================================
echo.
echo Le plugin S3 est maintenant installe sur votre serveur Proxmox.
echo Consultez la documentation pour la configuration avancee.
echo.
pause