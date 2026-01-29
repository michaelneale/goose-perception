#!/bin/bash
# Create a self-signed code signing certificate for GoosePerception
# This only needs to be run once. The certificate will be stored in your keychain.

set -e

CERT_NAME="GoosePerception Development"
CERT_FILE="goose-perception.p12"
CERT_PASSWORD="gooseperception"

# Check if certificate already exists in keychain
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ Certificate '$CERT_NAME' already exists in keychain"
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code signing certificate..."

# Create certificate using openssl
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Generate private key
openssl genrsa -out goose-perception.key 2048

# Create certificate signing request config
cat > goose-perception.conf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $CERT_NAME
O = GoosePerception
C = US

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:FALSE
EOF

# Generate self-signed certificate (valid for 10 years)
openssl req -new -x509 -key goose-perception.key -out goose-perception.crt \
    -days 3650 -config goose-perception.conf

# Create p12 file for keychain import (use legacy mode for compatibility)
openssl pkcs12 -export -out "$CERT_FILE" \
    -inkey goose-perception.key -in goose-perception.crt \
    -passout pass:$CERT_PASSWORD -legacy

echo ""
echo "Certificate created. Importing into keychain..."

# Import into login keychain
security import "$CERT_FILE" -k ~/Library/Keychains/login.keychain-db \
    -P "$CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -A

# Trust the certificate for code signing
echo "Adding certificate to trusted roots..."
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db goose-perception.crt 2>/dev/null || {
    echo ""
    echo "⚠️  Could not automatically trust the certificate."
    echo "   You may need to manually trust it:"
    echo "   1. Open Keychain Access"
    echo "   2. Find '$CERT_NAME' in 'login' keychain"
    echo "   3. Double-click it, expand 'Trust'"
    echo "   4. Set 'Code Signing' to 'Always Trust'"
    echo ""
}

# Verify
echo "Verifying certificate installation..."
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ Certificate installed successfully!"
    security find-identity -v -p codesigning | grep "$CERT_NAME"
else
    echo "❌ Certificate not found. You may need to trust it manually in Keychain Access."
fi

# Clean up temporary files
rm -f goose-perception.conf

echo ""
echo "Certificate files saved:"
echo "  - goose-perception.key (private key)"
echo "  - goose-perception.crt (certificate)"
echo "  - goose-perception.p12 (keychain bundle)"
