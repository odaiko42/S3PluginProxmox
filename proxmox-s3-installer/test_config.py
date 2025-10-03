#!/usr/bin/env python3
"""
Script de test pour l'installateur Proxmox S3
Simule une installation complète avec des données de test
"""

import sys
import os

# Ajouter le répertoire src au path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from installer.config_manager import ConfigManager

def test_config_manager():
    """Test du gestionnaire de configuration avec des données simulées"""
    print("=== TEST DU GESTIONNAIRE DE CONFIGURATION ===\n")
    
    config_manager = ConfigManager()
    
    # Configuration simulée MinIO
    config_manager.config = {
        'storage_name': 'minio-test',
        'bucket': 'test-bucket-proxmox',
        'endpoint': 'minio.example.com:9000',
        'region': 'us-east-1',
        'access_key': 'minioadmin',
        'secret_key': 'minioadmin123',
        'prefix': 'proxmox/',
        'content': 'backup,iso,vztmpl,snippets',
        'storage_class': 'STANDARD',
        'multipart_chunk_size': '100',
        'max_concurrent_uploads': '3'
    }
    
    print("Configuration MinIO simulée :")
    config_manager.show_config_preview()
    
    print("\n" + "="*60)
    print("Informations d'utilisation :")
    config_manager.display_information()
    
    print("\n" + "="*60)
    print("✓ Test du gestionnaire de configuration réussi!")

if __name__ == "__main__":
    test_config_manager()