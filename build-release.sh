#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="aerospace-codesign-certificate"
build_custom_app=0
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --custom-app) build_custom_app=1; shift 1;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build
cd -

git checkout .

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/AeroSpace.app" .release
cp -r .build/apple/Products/Release/aerospace .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace

################
### VALIDATE ###
################

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

validate-app-bundle() {
    app_name="$1"
    executable_name="$2"
    app_path=".release/$app_name"

    expected_layout=$(cat <<EOF
$app_path
$app_path/Contents
$app_path/Contents/_CodeSignature
$app_path/Contents/_CodeSignature/CodeResources
$app_path/Contents/MacOS
$app_path/Contents/MacOS/$executable_name
$app_path/Contents/Resources
$app_path/Contents/Resources/default-config.toml
$app_path/Contents/Resources/AppIcon.icns
$app_path/Contents/Resources/Assets.car
$app_path/Contents/Info.plist
$app_path/Contents/PkgInfo
EOF
    )

    if test "$expected_layout" != "$(find "$app_path")"; then
        echo "!!! Expect/Actual layout don't match !!!"
        find "$app_path"
        exit 1
    fi

    check-universal-binary "$app_path/Contents/MacOS/$executable_name"
    check-contains-hash "$app_path/Contents/MacOS/$executable_name"
    codesign -v "$app_path"
}

validate-app-bundle "AeroSpace.app" "AeroSpace"

if test "$build_custom_app" = 1; then
    xcodebuild-pretty .release/custom-xcodebuild.log clean build \
        -scheme AeroSpaceCustom \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build

    cp -r ".xcode-build/Build/Products/$xcode_configuration/AeroSpace Custom.app" .release
    validate-app-bundle "AeroSpace Custom.app" "AeroSpace Custom"
fi

############
### PACK ###
############

mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace "AeroSpace-v$build_version/bin"
    if test "$build_custom_app" = 1; then
        cp -r aerospace "AeroSpace-v$build_version/bin/aerospace-custom"
    fi
    cp -r AeroSpace.app "AeroSpace-v$build_version"
    zip -r "AeroSpace-v$build_version.zip" "AeroSpace-v$build_version"
cd -

#################
### Brew Cask ###
#################
if test "$build_custom_app" = 0; then
    for cask_name in aerospace aerospace-dev; do
        ./script/build-brew-cask.sh \
            --cask-name "$cask_name" \
            --zip-uri ".release/AeroSpace-v$build_version.zip" \
            --build-version "$build_version"
    done
fi
