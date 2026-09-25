#!/usr/bin/env bash
# Build RasterTools and publish it as a GitHub release versioned by today's date.
#
#   version  YYYY.M.D                  (CFBundleShortVersionString, shown in About)
#   build    git commit count          (CFBundleVersion, always increases)
#   tag      vYYYY.M.D, or vYYYY.M.D.N for the Nth release of the same day
#
# The release assets are always named RasterTools.zip and appcast.xml, so these links always
# serve the newest build and the in-app updater feed (SUFeedURL):
#   https://github.com/smart-hab/raster-tools/releases/latest/download/RasterTools.zip
#   https://github.com/smart-hab/raster-tools/releases/latest/download/appcast.xml
#
# The appcast is signed with the Sparkle EdDSA key in the login keychain (see CLAUDE.md).
set -euo pipefail

cd "$(dirname "$0")/.."

repo=https://github.com/smart-hab/raster-tools
packages=build/SourcePackages
sparkle_bin=$packages/artifacts/sparkle/Sparkle/bin

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree has uncommitted changes" >&2
    exit 1
fi

version=$(date +%Y.%-m.%-d)
build=$(git rev-list --count HEAD)

git fetch --tags --quiet origin
tag="v$version"
n=1
while git rev-parse -q --verify "refs/tags/$tag" >/dev/null; do
    n=$((n + 1))
    tag="v$version.$n"
done

echo "Building RasterTools $version (build $build), tag $tag"

rm -rf build/Release build/RasterTools.zip build/appcast
xcodebuild -scheme RasterTools -destination 'platform=macOS' -configuration Release \
    -clonedSourcePackagesDirPath "$packages" \
    SYMROOT=build MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    -quiet build

app=build/Release/RasterTools.app
plist="$app/Contents/Info.plist"
built_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")
built_build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
if [[ "$built_version" != "$version" || "$built_build" != "$build" ]]; then
    echo "error: built app reports $built_version ($built_build), expected $version ($build)" >&2
    exit 1
fi

# Installed copies only accept updates signed by the key they were built with.
built_key=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$plist")
signing_key=$("$sparkle_bin/generate_keys" -p)
if [[ -z "$built_key" || "$built_key" != "$signing_key" ]]; then
    echo "error: SUPublicEDKey in the app ('$built_key') does not match the keychain signing key" >&2
    exit 1
fi

ditto -c -k --keepParent "$app" build/RasterTools.zip

# generate_appcast signs every archive in the folder, so it gets a folder with just this one.
mkdir build/appcast
cp build/RasterTools.zip build/appcast/
"$sparkle_bin/generate_appcast" build/appcast \
    --download-url-prefix "$repo/releases/download/$tag/" \
    --full-release-notes-url "$repo/releases" \
    --link "$repo/releases/tag/$tag"
# generate_appcast skips signing without complaint when it can't, and Sparkle rejects unsigned updates.
if ! grep -q 'sparkle:edSignature=' build/appcast/appcast.xml; then
    echo "error: appcast.xml has no EdDSA signature" >&2
    exit 1
fi

git tag -a "$tag" -m "RasterTools $version (build $build)"
git push origin "$tag"

gh release create "$tag" build/RasterTools.zip build/appcast/appcast.xml \
    --title "RasterTools $version" \
    --generate-notes \
    --notes "Build $build. Requires macOS 26.2 or later.

**Install:** unzip, move RasterTools.app to Applications, and open it. The app isn't notarized yet, so macOS will block the first launch: go to System Settings → Privacy & Security and click **Open Anyway**. After that, the app updates itself (RasterTools → Check for Updates…)."

echo "Released $tag"
