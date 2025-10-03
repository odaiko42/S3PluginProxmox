#!/bin/bash

# Script de test MinIO S3 pour validation
# Usage: ./test-minio.sh [SERVER_IP]

SERVER_IP=${1:-"192.168.88.50"}
MINIO_PORT="9000"
CONSOLE_PORT="9001"
ACCESS_KEY="minioadmin"
SECRET_KEY="minioadmin123"
TEST_BUCKET="proxmox-test"

echo "=== Test MinIO S3 Server ==="
echo "Serveur: $SERVER_IP"
echo "Port API: $MINIO_PORT"
echo "Port Console: $CONSOLE_PORT"
echo ""

# Test 1: Connectivité de base
echo "🔍 Test 1: Connectivité de base"
if curl -s --connect-timeout 5 "http://$SERVER_IP:$MINIO_PORT" > /dev/null; then
    echo "✅ Port $MINIO_PORT accessible"
else
    echo "❌ Port $MINIO_PORT inaccessible"
    echo "   Vérifiez que MinIO est démarré et le firewall configuré"
fi

# Test 2: Health check
echo ""
echo "🔍 Test 2: Health check MinIO"
HEALTH_RESPONSE=$(curl -s "http://$SERVER_IP:$MINIO_PORT/minio/health/live" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✅ MinIO répond au health check"
else
    echo "❌ MinIO ne répond pas au health check"
fi

# Test 3: Console web
echo ""
echo "🔍 Test 3: Console web"
if curl -s --connect-timeout 5 "http://$SERVER_IP:$CONSOLE_PORT" > /dev/null; then
    echo "✅ Console web accessible sur port $CONSOLE_PORT"
    echo "   URL: http://$SERVER_IP:$CONSOLE_PORT"
else
    echo "❌ Console web inaccessible sur port $CONSOLE_PORT"
fi

# Test 4: API S3 (nécessite mc client)
echo ""
echo "🔍 Test 4: Test API S3 avec client mc"

# Vérifier si mc est installé
if command -v mc > /dev/null 2>&1; then
    # Configurer l'alias de test
    MC_ALIAS="test-$(date +%s)"
    
    if mc alias set "$MC_ALIAS" "http://$SERVER_IP:$MINIO_PORT" "$ACCESS_KEY" "$SECRET_KEY" > /dev/null 2>&1; then
        echo "✅ Authentification S3 réussie"
        
        # Test listing des buckets
        if mc ls "$MC_ALIAS" > /dev/null 2>&1; then
            echo "✅ Listing des buckets réussi"
            
            # Afficher les buckets existants
            BUCKETS=$(mc ls "$MC_ALIAS" 2>/dev/null | wc -l)
            echo "   Nombre de buckets: $BUCKETS"
            
            if mc ls "$MC_ALIAS" | grep -q "$TEST_BUCKET"; then
                echo "✅ Bucket de test '$TEST_BUCKET' trouvé"
            else
                echo "⚠️  Bucket de test '$TEST_BUCKET' non trouvé"
            fi
        else
            echo "❌ Échec du listing des buckets"
        fi
        
        # Nettoyer l'alias de test
        mc alias remove "$MC_ALIAS" > /dev/null 2>&1
    else
        echo "❌ Échec de l'authentification S3"
        echo "   Vérifiez les credentials: $ACCESS_KEY / $SECRET_KEY"
    fi
else
    echo "⚠️  Client 'mc' non installé, test API S3 ignoré"
    echo "   Pour installer: wget https://dl.min.io/client/mc/release/linux-amd64/mc"
fi

# Test 5: Test avec curl (API REST basique)
echo ""
echo "🔍 Test 5: Test API REST avec curl"

# Test simple GET sur le bucket
BUCKET_URL="http://$SERVER_IP:$MINIO_PORT/$TEST_BUCKET"
CURL_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "$BUCKET_URL" 2>/dev/null)

case "$CURL_RESPONSE" in
    200)
        echo "✅ Bucket '$TEST_BUCKET' accessible (HTTP 200)"
        ;;
    403)
        echo "✅ MinIO répond correctement (HTTP 403 - pas d'auth, normal)"
        ;;
    404)
        echo "⚠️  Bucket '$TEST_BUCKET' non trouvé (HTTP 404)"
        ;;
    *)
        echo "⚠️  Réponse inattendue: HTTP $CURL_RESPONSE"
        ;;
esac

# Test 6: Vérification des processus
echo ""
echo "🔍 Test 6: Processus MinIO (SSH requis)"
if command -v ssh > /dev/null 2>&1; then
    PROCESSES=$(ssh -o ConnectTimeout=5 root@$SERVER_IP "ps aux | grep -v grep | grep minio" 2>/dev/null)
    if [ -n "$PROCESSES" ]; then
        echo "✅ Processus MinIO en cours d'exécution"
        echo "   $(echo "$PROCESSES" | wc -l) processus trouvé(s)"
    else
        echo "❌ Aucun processus MinIO trouvé"
    fi
else
    echo "⚠️  SSH non disponible, test processus ignoré"
fi

# Résumé des tests
echo ""
echo "============================================"
echo "              RÉSUMÉ DES TESTS"
echo "============================================"
echo ""
echo "🌐 URLs importantes:"
echo "   API MinIO:     http://$SERVER_IP:$MINIO_PORT"
echo "   Console Web:   http://$SERVER_IP:$CONSOLE_PORT"
echo "   Health Check:  http://$SERVER_IP:$MINIO_PORT/minio/health/live"
echo ""
echo "🔑 Credentials de test:"
echo "   Access Key: $ACCESS_KEY"
echo "   Secret Key: $SECRET_KEY"
echo ""
echo "📋 Configuration Proxmox S3:"
echo "   Endpoint:   $SERVER_IP:$MINIO_PORT"
echo "   Bucket:     $TEST_BUCKET"
echo "   Use SSL:    Non"
echo "   Region:     us-east-1"
echo ""

# Test de performance simple (optionnel)
echo "🚀 Test de performance (ping):"
if command -v ping > /dev/null 2>&1; then
    PING_RESULT=$(ping -c 3 "$SERVER_IP" 2>/dev/null | grep "avg" | cut -d'/' -f5)
    if [ -n "$PING_RESULT" ]; then
        echo "   Latence moyenne: ${PING_RESULT}ms"
    else
        echo "   Impossible de mesurer la latence"
    fi
else
    echo "   Commande ping non disponible"
fi

echo ""
echo "=== Test terminé ==="