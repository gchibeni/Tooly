#!/usr/bin/env bash
set -e
# -------------------------------
# Variables.
# -------------------------------
PROJECT_NAME="findersyncext"   # XcodeGen project name
TARGET_NAME="tooly-findersync"             # FinderSync target name
SCHEME_NAME="$TARGET_NAME"           # scheme usually same as target
CONFIGURATION="Release"              # or Debug
BUILD_DIR="./build"                  # local output folder
TAURI_BUNDLE_DIR="../src-tauri/target/release/bundle/macos"  # Tauri macOS bundles
# -------------------------------
# Builder.
# -------------------------------
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
# -------------------------------
# Bundler.
# -------------------------------
read -p "Do you want to bundle into Tauri application? [Y]es/[N]o: " response
response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
if [[ "$response" == "y" || "$response" == "yes" ]]; then
    # Find the built app.
    APP_PATH=$(ls -td $TAURI_BUNDLE_DIR/*.app | head -n 1)
    if [[ ! -d "$APP_PATH" ]]; then
        echo "❌ Tauri app bundle not found. Make sure you run 'npm run tauri build' first."
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
