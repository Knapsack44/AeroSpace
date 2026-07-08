#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

./generate.sh --build-version "$build_version" --ignore-cmd-help --ignore-shell-parser

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors

xcodebuild -project AeroSpace.xcodeproj \
    -scheme AeroSpaceCustom \
    -destination "generic/platform=macOS" \
    -configuration Release \
    -derivedDataPath .xcode-build-custom \
    CODE_SIGNING_ALLOWED=NO \
    build

rm -rf "/Applications/AeroSpace Custom.app"
cp -r ".xcode-build-custom/Build/Products/Release/AeroSpace Custom.app" /Applications
xattr -dr com.apple.quarantine "/Applications/AeroSpace Custom.app" 2>/dev/null || true
codesign --force --sign - "/Applications/AeroSpace Custom.app"

if command -v brew >/dev/null 2>&1; then
    bin_dir="$(brew --prefix)/bin"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    bin_dir="$(/opt/homebrew/bin/brew --prefix)/bin"
elif [[ -d /opt/homebrew/bin ]]; then
    bin_dir="/opt/homebrew/bin"
else
    bin_dir="/usr/local/bin"
fi

cp -f .build/apple/Products/Release/aerospace "$bin_dir/aerospace-custom"

echo "Installed /Applications/AeroSpace Custom.app"
echo "Installed $bin_dir/aerospace-custom"
