#!/bin/bash
# Signs the built Negoto.app with a certificate + provisioning profile and packages an IPA.
# The bundle ID and iCloud container are taken from the profile, so any team can use it.
#
# Usage: sign_ipa.sh <Negoto.app> <cert.p12> <p12 password> <profile.mobileprovision> <output.ipa>
set -euo pipefail

APP_IN="$1"; P12="$2"; P12_PASSWORD="$3"; PROFILE="$4"; OUT="$5"
WORK="$(mktemp -d)"
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

cleanup() { security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

# Temporary keychain with the signing identity
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1 {print $2}')"
test -n "$IDENTITY" || { echo "No signing identity found in the certificate"; exit 1; }

# Decode the profile and derive bundle ID, entitlements and iCloud container
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
mkdir -p "$WORK/Payload"
cp -R "$APP_IN" "$WORK/Payload/"
APP="$WORK/Payload/$(basename "$APP_IN")"
cp "$PROFILE" "$APP/embedded.mobileprovision"

python3 - "$WORK/profile.plist" "$APP/Info.plist" "$WORK/entitlements.plist" <<'PY'
import plistlib, sys
profile_path, info_path, ent_path = sys.argv[1:4]
profile = plistlib.load(open(profile_path, "rb"))
info = plistlib.load(open(info_path, "rb"))
pent = profile.get("Entitlements", {})
team = profile["TeamIdentifier"][0]
app_id = pent["application-identifier"]
bundle = app_id.split(".", 1)[1]
if "*" in bundle:  # wildcard profile: keep the app's own bundle ID
    bundle = info["CFBundleIdentifier"]
info["CFBundleIdentifier"] = bundle
development = bool(pent.get("get-task-allow"))
ent = {
    "application-identifier": f"{team}.{bundle}",
    "com.apple.developer.team-identifier": team,
    "get-task-allow": development,
    "keychain-access-groups": [f"{team}.{bundle}"],
}
containers = [c for c in pent.get("com.apple.developer.icloud-container-identifiers", []) if "*" not in c]
if containers:
    ent["com.apple.developer.icloud-container-identifiers"] = containers
    ent["com.apple.developer.icloud-services"] = ["CloudDocuments"]
    ubiquity = [c for c in pent.get("com.apple.developer.ubiquity-container-identifiers", containers) if "*" not in c]
    ent["com.apple.developer.ubiquity-container-identifiers"] = ubiquity or containers
    env = pent.get("com.apple.developer.icloud-container-environment")
    if isinstance(env, list):
        ent["com.apple.developer.icloud-container-environment"] = "Development" if development else "Production"
    elif isinstance(env, str):
        ent["com.apple.developer.icloud-container-environment"] = env
    info["NSUbiquitousContainers"] = {containers[0]: {
        "NSUbiquitousContainerIsDocumentScopePublic": True,
        "NSUbiquitousContainerName": "Negoto",
        "NSUbiquitousContainerSupportedFolderLevels": "Any",
    }}
    print(f"iCloud container: {containers[0]}")
else:
    info.pop("NSUbiquitousContainers", None)
    print("Profile has no iCloud container: the app will use folder-based iCloud Drive sync.")
plistlib.dump(info, open(info_path, "wb"))
plistlib.dump(ent, open(ent_path, "wb"))
print(f"Bundle ID: {bundle}  Team: {team}  ({'development' if development else 'distribution'})")
PY

# Sign nested code first, then the app
find "$APP" -mindepth 1 \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) -print0 |
  while IFS= read -r -d '' item; do
    codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" "$item"
  done
codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$WORK/entitlements.plist" --generate-entitlement-der "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | head -40 || true

(cd "$WORK" && ditto -c -k --sequesterRsrc --keepParent Payload signed.ipa)
mv "$WORK/signed.ipa" "$OUT"
echo "Signed IPA: $OUT"
