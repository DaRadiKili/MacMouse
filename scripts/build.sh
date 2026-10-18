#!/bin/zsh
# Baut MacMouse als App (build/MacMouse.app) und signiert es mit einem eigenen, lokalen Zertifikat.
# Warum: macOS bindet Bedienungshilfen-/Eingabeüberwachungs-Rechte an die Signatur. Mit einer festen Signatur
# bleiben die Rechte nach jedem Neubau erhalten. Das Zertifikat liegt in einem eigenen Schlüsselbund unter
# ~/.config/macmouse/ (nicht in deinem Login-Schlüsselbund) und lässt sich einfach löschen.
set -e
cd "$(dirname "$0")/.."

KC="$HOME/.config/macmouse/signing.keychain-db"
# Frühere Versionen hießen "maus" und legten den Schlüsselbund unter ~/.config/maus ab
[ -f "$KC" ] || { [ -f "$HOME/.config/maus/signing.keychain-db" ] && KC="$HOME/.config/maus/signing.keychain-db"; }
IDENTITY="maus-local-signing"
BUNDLE_ID="de.maus.agent"   # bleibt so, damit erteilte Berechtigungen nach der Umbenennung gültig bleiben

mkdir -p build
swiftc -O -swift-version 5 src/*.swift -o build/MacMouse

if [ ! -f "$KC" ]; then
    echo "Lege lokales Signier-Zertifikat an …"
    mkdir -p "$HOME/.config/macmouse"
    T=$(mktemp -d)
    cat > "$T/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cert.cnf" \
        -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -out "$T/id.p12" -passout pass:macmouse 2>/dev/null
    security create-keychain -p "" "$KC"
    security set-keychain-settings "$KC"
    security unlock-keychain -p "" "$KC"
    security import "$T/id.p12" -k "$KC" -P macmouse -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KC" >/dev/null
    rm -rf "$T"
fi
security unlock-keychain -p "" "$KC"

# --- App-Paket ---
APP=build/MacMouse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/MacMouse "$APP/Contents/MacOS/MacMouse"

# Symbol
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O scripts/make-icon.swift -o build/make-icon 2>/dev/null
build/make-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/make-icon

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>MacMouse</string>
    <key>CFBundleDisplayName</key><string>MacMouse</string>
    <key>CFBundleExecutable</key><string>MacMouse</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "$IDENTITY" --keychain "$KC" --identifier "$BUNDLE_ID" "$APP"
codesign --force --sign "$IDENTITY" --keychain "$KC" --identifier "$BUNDLE_ID" build/MacMouse
echo "Fertig: build/MacMouse.app"
