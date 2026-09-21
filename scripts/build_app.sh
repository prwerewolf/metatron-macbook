#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=========================================="
echo "  Building Metatron for macOS (Apple M4 Max)"
echo "=========================================="

APP_NAME="Metatron"
BUILD_CONFIG="release"

# 1. Compile Swift executable
echo "Compiling Swift executable ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG"

EXECUTABLE_PATH="$DIR/.build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 2. Recreate .app bundle structure
echo "Packaging $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy binary
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 4. Copy Info.plist
cp "$DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# 5. Copy local MLX daemon to resources
cp "$DIR/daemon/whisper_daemon.py" "$RESOURCES_DIR/whisper_daemon.py"
chmod +x "$RESOURCES_DIR/whisper_daemon.py"

# 6. Copy AppIcon.icns & AppIcon_master.png
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$DIR/Resources/AppIcon_master.png" ]; then
    cp "$DIR/Resources/AppIcon_master.png" "$RESOURCES_DIR/AppIcon_master.png"
fi

# 7. Code signing with stable identity (preserves macOS Accessibility / TCC permissions across rebuilds)
SIGNING_IDENTITY="Metatron Development"

if ! security find-identity -p codesigning | grep -q "\"$SIGNING_IDENTITY\""; then
    echo "Creating persistent local developer certificate '$SIGNING_IDENTITY'..."
    CERT_DIR="$DIR/.build/certs"
    mkdir -p "$CERT_DIR"

    cat << 'EOF' > "$CERT_DIR/cert.cnf"
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[ dn ]
CN = Metatron Development

[ v3_ca ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

    openssl req -new -x509 -days 3650 -nodes -config "$CERT_DIR/cert.cnf" \
        -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" 2>/dev/null

    openssl pkcs12 -export -out "$CERT_DIR/cert.p12" \
        -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
        -password pass:metatron -legacy 2>/dev/null || \
    openssl pkcs12 -export -out "$CERT_DIR/cert.p12" \
        -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
        -password pass:metatron 2>/dev/null

    security import "$CERT_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db -P metatron -A
fi

if security find-identity -p codesigning | grep -q "\"$SIGNING_IDENTITY\""; then
    echo "Codesigning bundle with persistent identity '$SIGNING_IDENTITY'..."
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    echo "Falling back to ad-hoc codesigning..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "=========================================="
echo "  Successfully built: $APP_BUNDLE"
echo "=========================================="
