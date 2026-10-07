# LumeToggle — menu bar toggle for Lume Cube panels.
#
# No Xcode project and no SwiftPM package: `swiftc` compiles Sources/
# straight into a hand-assembled .app, and the rest signs, notarises
# and packages.
#
#   just run          build, bundle and launch — the dev loop
#   just bundle       assemble LumeToggle.app (ad-hoc signed)
#   just dist         bundle + sign + notarise + dmg
#
# Requires: Xcode command line tools, `just`, and a Developer ID in the
# login keychain for anything past `bundle`.

app_name  := "LumeToggle"
# arm64 only, matching the CELS panel. The minimum OS here must agree
# with LSMinimumSystemVersion in Info.plist.
target    := "arm64-apple-macos13.0"
build_dir := justfile_directory() / "build"
app_dir   := build_dir / (app_name + ".app")
dmg       := build_dir / (app_name + ".dmg")
# A notary profile is just stored Apple ID credentials, not tied to an
# app, so the one CELS already created is reused.
notary    := env_var_or_default("NOTARY_PROFILE", "cels-notary")

default:
    @just --list

# Ad-hoc signed even for dev builds. Bluetooth permission is granted per
# code signature; an unsigned bundle gets re-prompted or silently
# refused after every rebuild.
[group('build')]
[doc('Assemble the .app bundle')]
bundle:
    rm -rf "{{app_dir}}"
    mkdir -p "{{app_dir}}/Contents/MacOS" "{{app_dir}}/Contents/Resources"
    swiftc -O -target {{target}} -o "{{app_dir}}/Contents/MacOS/{{app_name}}" Sources/*.swift
    cp Info.plist "{{app_dir}}/Contents/Info.plist"
    cp Resources/AppIcon.icns "{{app_dir}}/Contents/Resources/"
    codesign --force --sign - "{{app_dir}}"
    @echo "built {{app_dir}}"

# The icon is drawn in code, like the menu bar glyph it is based on. The
# .icns is checked in, so this only needs rerunning after editing the script.
[group('build')]
[doc('Regenerate Resources/AppIcon.icns from scripts/make_icon.swift')]
icon:
    #!/usr/bin/env bash
    set -euo pipefail
    SET=$(mktemp -d)/AppIcon.iconset
    swift scripts/make_icon.swift "$SET"
    iconutil -c icns -o Resources/AppIcon.icns "$SET"
    rm -rf "$(dirname "$SET")"
    echo "wrote Resources/AppIcon.icns"

# Build, bundle and launch.
#
# Quits the running copy first: `open` on an already-running app just
# reactivates it, so the new build would never start.
[group('build')]
[doc('Build, bundle and launch')]
run: bundle
    -pkill -x {{app_name}}
    open "{{app_dir}}"

# Sign with a Developer ID and the hardened runtime.
#
# No entitlements file: Bluetooth under the hardened runtime needs only
# NSBluetoothAlwaysUsageDescription, and CameraMonitor reads CoreMediaIO
# device state without opening a camera, so it needs no camera
# entitlement. Add one here if that ever changes.
[group('package')]
[doc('Sign with a Developer ID and the hardened runtime')]
sign: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -n 's/.*"\(.*\)"/\1/p')
    if [ -z "$ID" ]; then
        echo "error: no Developer ID Application certificate in the keychain" >&2
        exit 1
    fi
    echo "signing as: $ID"
    codesign --force --options runtime --timestamp --sign "$ID" "{{app_dir}}"
    codesign --verify --verbose=2 "{{app_dir}}"

# Notarise and staple.
#
# Needs APPLE_ID and APPLE_APP_PASSWORD (an app-specific password from
# appleid.apple.com, not the account password) only if the keychain
# profile doesn't exist yet; otherwise it prompts.
[group('package')]
[doc('Notarise and staple')]
notarize: sign
    #!/usr/bin/env bash
    set -euo pipefail
    PROFILE="{{notary}}"
    if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        echo "No notary profile '$PROFILE' yet — storing one."
        # Interactive by default so the password goes into a prompt, not
        # the process table or shell history.
        TEAM=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -n 's/.*(\(.*\)).*/\1/p')
        if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
            xcrun notarytool store-credentials "$PROFILE" \
                --apple-id "$APPLE_ID" --team-id "$TEAM" --password "$APPLE_APP_PASSWORD"
        else
            xcrun notarytool store-credentials "$PROFILE" --team-id "$TEAM"
        fi
    fi
    ZIP="{{build_dir}}/notarize.zip"
    ditto -c -k --keepParent "{{app_dir}}" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "{{app_dir}}"
    rm -f "$ZIP"

# Build the distributable disk image.
[group('package')]
dmg: notarize
    #!/usr/bin/env bash
    set -euo pipefail
    rm -f "{{dmg}}"
    STAGE=$(mktemp -d)
    cp -R "{{app_dir}}" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "{{app_name}}" -srcfolder "$STAGE" \
        -ov -format UDZO "{{dmg}}"
    rm -rf "$STAGE"
    ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -n 's/.*"\(.*\)"/\1/p')
    codesign --sign "$ID" --timestamp "{{dmg}}"
    # The DMG is what gets downloaded, so Gatekeeper judges it, not the
    # app inside: a signed but unnotarised DMG is rejected even when its
    # app is notarised. Both are stapled so each passes offline.
    xcrun notarytool submit "{{dmg}}" --keychain-profile "{{notary}}" --wait
    xcrun stapler staple "{{dmg}}"
    echo "built {{dmg}}"

# The whole chain.
[group('package')]
dist: dmg

# Check the bundle the way another Mac will.
#
# Gatekeeper trusts a locally built binary and quarantines a downloaded
# one, so notarisation problems are invisible without this.
[group('package')]
[doc('Check the bundle the way another Mac will')]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== app =="
    xcrun stapler validate "{{app_dir}}"
    spctl -a -vvv -t exec "{{app_dir}}"
    echo
    echo "== dmg =="
    xcrun stapler validate "{{dmg}}"
    spctl -a -vvv -t open --context context:primary-signature "{{dmg}}"

[group('build')]
[doc('Remove build output')]
clean:
    rm -rf "{{build_dir}}"
