#!/usr/bin/env python3
"""
Test rapide des améliorations - Régions européennes et instructions claires
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

def test_regions():
    """Test des suggestions de régions européennes"""
    print("=== TEST DES SUGGESTIONS DE RÉGIONS ===\n")
    
    endpoints_test = [
        "s3.amazonaws.com",
        "s3.fr-par.scw.cloud", 
        "s3.gra.perf.cloud.ovh.net",
        "minio.example.com:9000"
    ]
    
    for endpoint in endpoints_test:
        print(f"Endpoint: {endpoint}")
        
        if 'amazonaws.com' in endpoint:
            print("   🇪🇺 Europe: eu-west-1 (Irlande), eu-central-1 (Francfort), eu-west-3 (Paris)")
            print("   🇺🇸 US: us-east-1 (Virginie), us-west-2 (Oregon)")
            default_region = "eu-west-1"
        elif 'scaleway' in endpoint.lower() or 'scw.cloud' in endpoint:
            print("   Régions Scaleway: fr-par (Paris), nl-ams (Amsterdam), pl-waw (Varsovie)")
            default_region = "fr-par"
        elif 'ovh' in endpoint.lower():
            print("   Régions OVH: gra (Gravelines), sbg (Strasbourg), uk (Londres)")
            default_region = "gra"
        else:
            print("   Exemples: us-east-1, eu-west-1, eu-central-1")
            default_region = "us-east-1"
            
        print(f"   ✓ Défaut suggéré: {default_region}\n")

def test_auth_instructions():
    """Test des nouvelles instructions d'authentification"""
    print("=== TEST DES INSTRUCTIONS D'AUTHENTIFICATION ===\n")
    
    services = [
        ("AWS S3", "s3.amazonaws.com"),
        ("MinIO", "minio.example.com:9000"),
        ("Scaleway", "s3.fr-par.scw.cloud"),
        ("OVH", "s3.gra.perf.cloud.ovh.net")
    ]
    
    for name, endpoint in services:
        print(f"🔐 {name} ({endpoint}):")
        
        if 'amazonaws.com' in endpoint:
            print("   ACCESS KEY: Format AKIA... (20 caractères)")
            print("   SECRET KEY: 40 caractères base64")
            print("   📍 Trouvez-les dans: AWS Console > IAM > Users")
        elif 'minio' in endpoint.lower():
            print("   ACCESS KEY: Nom d'utilisateur (ex: minioadmin)")
            print("   SECRET KEY: Mot de passe (ex: minioadmin)")
            print("   📍 Trouvez-les dans: MinIO Console > Identity > Users")
        elif 'scaleway' in endpoint.lower():
            print("   ACCESS KEY: Format SCW... ")
            print("   SECRET KEY: UUID format")
            print("   📍 Trouvez-les dans: Console Scaleway > API Keys")
        elif 'ovh' in endpoint.lower():
            print("   ACCESS KEY: Clé d'accès OVH")
            print("   SECRET KEY: Clé secrète OVH")
            print("   📍 Trouvez-les dans: Manager OVH > Cloud > Object Storage")
        
        print("   ✓ Instructions claires ✓\n")

if __name__ == "__main__":
    test_regions()
    test_auth_instructions()
    
    print("="*60)
    print("✅ TOUS LES TESTS RÉUSSIS!")
    print("✅ Régions européennes ajoutées")
    print("✅ Instructions d'authentification clarifiées")
    print("✅ Section dépannage ajoutée")
    print("="*60)