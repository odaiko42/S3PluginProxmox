#!/bin/bash

# Script de diagnostic et correction S3
echo "=== Diagnostic Stockage S3 Proxmox ==="
echo ""

echo "1. Test de connectivité MinIO..."
curl -I http://192.168.88.90:9000 2>/dev/null && echo "✓ MinIO accessible" || echo "✗ MinIO inaccessible"
echo ""

echo "2. Statut du container MinIO..."
pct status 106
echo ""

echo "3. Test avec credentials par défaut MinIO..."
# Tester avec minioadmin/minioadmin (credentials par défaut)
curl -s -X GET "http://192.168.88.90:9000/" \
  -H "Authorization: AWS4-HMAC-SHA256 Credential=minioadmin/20251003/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-date, Signature=test" 2>/dev/null | head -1

echo ""
echo "4. Configuration actuelle du stockage S3..."
grep -A 8 "s3: s3-storage" /etc/pve/storage.cfg
echo ""

echo "5. Test manuel de l'API S3..."
# Test simple avec curl
response=$(curl -s -w "%{http_code}" -o /dev/null "http://minioadmin:minioadmin@192.168.88.90:9000/test-bucket")
echo "Code de réponse HTTP: $response"
echo ""

echo "6. Logs pvedaemon pour S3..."
journalctl -u pvedaemon --since "5 minutes ago" | grep -i "s3\|storage" | tail -5
echo ""

echo "7. Suggestions de correction:"
echo "- Vérifier les credentials MinIO réels"
echo "- Vérifier que le bucket 'test-bucket' existe"
echo "- Tester avec les credentials par défaut minioadmin/minioadmin"
echo "- Reconfigurer le stockage S3 avec les bons paramètres"