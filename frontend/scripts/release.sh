#!/usr/bin/env bash
# Build RasterTools and publish it as a GitHub release versioned by today's date.
#
#   version  YYYY.M.D                  (CFBundleShortVersionString, shown in About)
#   build    git commit count          (CFBundleVersion, always increases)
#   tag      vYYYY.M.D, or vYYYY.M.D.N for the Nth release of the same day
#
# The release asset is always named RasterTools.zip, so this link always serves the newest build:
#   https://github.com/smart-hab/raster-tools/releases/latest/download/RasterTools.zip
set -euo pipefail

cd "$(dirname "$0")/.."

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

rm -rf build/Release build/RasterTools.zip
xcodebuild -scheme RasterTools -destination 'platform=macOS' -configuration Release \
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

ditto -c -k --keepParent "$app" build/RasterTools.zip

git tag -a "$tag" -m "RasterTools $version (build $build)"
git push origin "$tag"

gh release create "$tag" build/RasterTools.zip \
    --title "RasterTools $version" \
    --generate-notes \
    --notes "Build $build. Requires macOS 26.2 or later.

**Install:** unzip, move RasterTools.app to Applications, and open it. The app isn't notarized yet, so macOS will block the first launch: go to System Settings → Privacy & Security and click **Open Anyway**."

echo "Released $tag"
