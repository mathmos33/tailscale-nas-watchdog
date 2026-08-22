#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/TailscaleNAS.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if ! command -v swiftc &>/dev/null; then
    echo "==> ERROR: swiftc not found. Install the Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi

# CLT 15.3 ships a broken module.modulemap (duplicate "module SwiftBridging"
# definition) that breaks any compile, and its swiftc is Swift 5.10, too old
# to parse the @_extern-based Swift.swiftmodule from newer SDKs if a partial
# upgrade leaves a mismatched SDK/compiler pair. Require Swift 6+ to catch
# both failure modes with a clear message instead of a wall of module/linker
# errors.
SWIFT_VERSION_MAJOR=$(swiftc --version 2>&1 | grep -oE 'Swift version [0-9]+' | grep -oE '[0-9]+' | head -1)
if [[ -z "$SWIFT_VERSION_MAJOR" || "$SWIFT_VERSION_MAJOR" -lt 6 ]]; then
    echo "==> ERROR: swiftc is too old ($(swiftc --version 2>&1 | head -1))."
    echo "    Command Line Tools 15.3 has a known bug (duplicate SwiftBridging"
    echo "    module) and ships Swift 5.10, which can't build this project."
    echo "    Install Command Line Tools 16.2 or newer:"
    echo "      sudo rm -rf /Library/Developer/CommandLineTools"
    echo "      sudo softwareupdate --install \"Command Line Tools for Xcode-16.2\" --agree-to-license"
    echo "    Then verify with: swiftc --version  (must show Swift 6.x)"
    echo "    If macOS's background updater silently reverts this, disable"
    echo "    automatic updates in System Settings > General > Software Update"
    echo "    before reinstalling."
    exit 1
fi

case "$(uname -m)" in
    arm64)  SWIFT_TARGET="arm64-apple-macosx11.0" ;;
    x86_64) SWIFT_TARGET="x86_64-apple-macosx11.0" ;;
    *)      echo "==> ERROR: unsupported architecture $(uname -m)"; exit 1 ;;
esac

echo "Compiling TailscaleNASApp.swift..."
swiftc -O -target "$SWIFT_TARGET" "$DIR/TailscaleNASApp.swift" -o "$APP/Contents/MacOS/TailscaleNAS"

cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/TailscaleNAS"

# Ad-hoc signing (--sign -) gives the binary a fresh identity hash on every
# rebuild, which invalidates any TCC grant (Full Disk Access, Network
# Volumes) the user already gave the app — silently, no re-prompt — so the
# Spotlight-flag write breaks again after every `install.sh`. A stable
# self-signed certificate keeps the same signing identity across rebuilds,
# so TCC grants survive. Created once per machine, reused after that.
CERT_NAME="TailscaleNAS Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

ensure_signing_identity() {
    if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
        return 0
    fi

    echo "==> No local code-signing certificate found, creating '$CERT_NAME' (one-time, persists across rebuilds)..."
    # Pinned to the system LibreSSL, not whatever's first on PATH: OpenSSL 3.x
    # (e.g. Homebrew's) defaults to a PKCS12 cipher/MAC macOS's `security
    # import` can't read ("MAC verification failed"), while /usr/bin/openssl
    # is guaranteed present and known-compatible.
    local OPENSSL=/usr/bin/openssl
    local tmp pass
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    pass=$("$OPENSSL" rand -base64 24)

    cat >"$tmp/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no

[dn]
CN = $CERT_NAME

[v3_ext]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

    if ! "$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
            -days 3650 -nodes -config "$tmp/ext.cnf" >/dev/null 2>&1; then
        echo "==> WARNING: could not generate the local certificate, falling back to ad-hoc signing."
        return 1
    fi

    "$OPENSSL" pkcs12 -export -out "$tmp/cert.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -passout "pass:$pass" >/dev/null 2>&1

    security import "$tmp/cert.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
    security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

    if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
        echo "==> WARNING: certificate created but not usable for signing, falling back to ad-hoc."
        return 1
    fi
    echo "==> Certificate created and trusted for code signing."
}

if ensure_signing_identity; then
    SIGN_IDENTITY="$CERT_NAME"
else
    SIGN_IDENTITY="-"
fi

echo "Signing ($SIGN_IDENTITY)..."
if ! codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP" 2>/tmp/codesign-err.$$; then
    cat /tmp/codesign-err.$$ >&2
    rm -f /tmp/codesign-err.$$
    echo "==> Signing with '$SIGN_IDENTITY' failed, retrying ad-hoc..."
    codesign --force --deep --sign - "$APP"
fi
rm -f /tmp/codesign-err.$$

echo "Built $APP"
