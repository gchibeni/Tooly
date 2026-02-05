#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
#region Variables

PROJECT_NAME="findersyncext"
TARGET_NAME="tooly-findersync"
SCHEME_NAME="$TARGET_NAME"
CONFIGURATION="Release"
BUILD_DIR="./build"
TAURI_BUNDLE_DIR="../src-tauri/target/release/bundle/macos"

#endregion

#region Builder

mkdir -p "$BUILD_DIR"
echo "Building FinderSync.appex..."
xcodebuild \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath ./DerivedData \
  build
APP_EXE_PATH="./DerivedData/Build/Products/$CONFIGURATION/$TARGET_NAME.appex"
cp -R "$APP_EXE_PATH" "$BUILD_DIR/"
echo "✅ FinderSync.appex copied to $BUILD_DIR/$TARGET_NAME.appex"

#endregion

#region Bundler

# Check for arguments.
if [[ "$1" == "--y" ]]; then
    BUNDLE=true
elif [[ "$1" == "--n" ]]; then
    BUNDLE=false
else
    # Repeat question until valid answer.
    while true; do
    read -p "Do you want to bundle extension into application? [Y]es/[N]o: " response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

    if [[ "$response" == "y" || "$response" == "yes" ]]; then
        BUNDLE=true
        break
    elif [[ "$response" == "n" || "$response" == "no" ]]; then
        BUNDLE=false
        break
    fi
    done
fi

if $BUNDLE; then
    # Find the built app.
    APP_PATH=$(ls -td $TAURI_BUNDLE_DIR/*.app | head -n 1)
    if [[ ! -d "$APP_PATH" ]]; then
        echo "❌ App bundle not found. Make sure you run 'npm run tauri build' first."
        exit 1
    fi
    # Create PlugIns folder if it doesn't exist.
    PLUGINS_DIR="$APP_PATH/Contents/PlugIns"
    mkdir -p "$PLUGINS_DIR"
    # Copy .appex to app.
    cp -R "$BUILD_DIR/$TARGET_NAME.appex" "$PLUGINS_DIR/"
    echo "✅ FinderSync.appex bundled into $APP_PATH/Contents/PlugIns/"
else
    echo "Skipping bundle."
    exit 0
fi

#endregion
