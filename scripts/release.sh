#!/bin/bash
# Signed, notarized HeadsUp release: a DMG for new installs, a zip + appcast.xml for Sparkle.
#
#   scripts/release.sh 1.2.0            # builds into build/release, touches nothing remote
#   scripts/release.sh 1.2.0 --publish  # also commits the bump, tags, pushes, creates the GitHub release
#
# File names never change, so links to releases/latest/download/HeadsUp.dmg keep working
# and installed copies read appcast.xml from the latest release (SUFeedURL).
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh <version> [--publish]}"
publish="${2:-}"
repo="ion05/headsup"
sign_id="Developer ID Application: Aayan Agarwal (27UZT2RBW3)"
profile="${NOTARY_PROFILE:-mix-notary}"
pb=/usr/libexec/PlistBuddy
out=build/release
app=build/HeadsUp.app

# ponytail: untracked files don't count, and Info.plist may hold an unpublished bump from a dry run.
if [ -n "$(git status --porcelain --untracked-files=no -- . ':!Info.plist')" ]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi

# A new version gets the next build number; the same version is a repackage and keeps its
# build. So the committed 1.0.0 / build 1 ships as-is, and re-running a dry run never double-bumps.
if [ "$($pb -c 'Print CFBundleShortVersionString' Info.plist)" != "$version" ]; then
    next=$(( $($pb -c 'Print CFBundleVersion' Info.plist) + 1 ))
    $pb -c "Set CFBundleShortVersionString $version" -c "Set CFBundleVersion $next" Info.plist
fi
build=$($pb -c 'Print CFBundleVersion' Info.plist)

# Sparkle only offers a build higher than the installed one. The feed 404s while the repo is
# private or before the first release; then there is nothing to compare against.
feed=$(curl -fsL "https://github.com/$repo/releases/latest/download/appcast.xml" 2>/dev/null || true)
published=$(printf '%s' "$feed" | sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p')
published_version=$(printf '%s' "$feed" | sed -n 's:.*<sparkle\:shortVersionString>\(.*\)</sparkle\:shortVersionString>.*:\1:p')
if [ -n "$published" ] && { [ "$build" -lt "$published" ] || { [ "$build" -eq "$published" ] && [ "$version" != "$published_version" ]; }; }; then
    echo "Build $build is not higher than the published build $published." >&2
    exit 1
fi

UNIVERSAL=1 INSTALL=0 SIGN_ID="$sign_id" ./build.sh

notarize() { xcrun notarytool submit "$1" --keychain-profile "$profile" --wait; }
rm -rf "$out"
mkdir -p "$out"

# The app: notarize a throwaway zip, staple the ticket, then zip the stapled app for Sparkle.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
notarize "$out/notarize.zip"
rm "$out/notarize.zip"
xcrun stapler staple "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/HeadsUp.zip"

# The DMG: 660x400 window, app left of the arrow, Applications right (design/dmg-background.tiff).
# create-dmg lays the window out through Finder, so a window flashes up for a few seconds.
stage=$(mktemp -d)
ditto "$app" "$stage/HeadsUp.app"
create-dmg \
    --volname "HeadsUp" \
    --volicon design/AppIcon.icns \
    --background design/dmg-background.tiff \
    --window-size 660 400 \
    --icon-size 112 \
    --text-size 13 \
    --icon "HeadsUp.app" 165 185 \
    --hide-extension "HeadsUp.app" \
    --app-drop-link 495 185 \
    --no-internet-enable \
    "$out/HeadsUp.dmg" "$stage" >/dev/null
rm -rf "$stage"
codesign --sign "$sign_id" --timestamp "$out/HeadsUp.dmg"
notarize "$out/HeadsUp.dmg"
xcrun stapler staple "$out/HeadsUp.dmg"

# Signs with the EdDSA key generate_keys saved in the login keychain (shared with Mix).
signature=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$out/HeadsUp.zip")
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>HeadsUp</title>
    <item>
      <title>Version $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$repo/releases/tag/v$version</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/v$version/HeadsUp.zip" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML

echo "HeadsUp $version (build $build) is ready in $out: HeadsUp.dmg, HeadsUp.zip, appcast.xml"

if [ "$publish" != "--publish" ]; then
    echo "Next: commit Info.plist if it changed, then run again with --publish (or upload the three files"
    echo "to a GitHub release tagged v$version and mark it Latest)."
    exit 0
fi

git diff --quiet Info.plist || git commit -m "Release $version" -- Info.plist
git tag "v$version"
git push origin HEAD "v$version"
# ponytail: substring match on the version in "## " headings; anchor it if versions start colliding.
notes=$(awk -v v="$version" '/^## /{p = index($0, v) > 0; next} p' CHANGELOG.md 2>/dev/null || true)
gh release create "v$version" "$out/HeadsUp.dmg" "$out/HeadsUp.zip" "$out/appcast.xml" \
    --repo "$repo" --title "HeadsUp $version" --notes "${notes:-HeadsUp $version}"
