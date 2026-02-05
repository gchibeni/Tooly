#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
#region Variables

TAURI_BUNDLE_DIR="../src-tauri/target/release/bundle/macos"
APP_NAME="tooly.app"
TAURI_APP_PATH="$TAURI_BUNDLE_DIR/$APP_NAME"
PLUGINS_DIR="$TAURI_APP_PATH/Contents/PlugIns"
ENTITLEMENTS="./.entitlements"

#endregion

#region Identities

IDENTITIES=()
while IFS= read -r line; do
  IDENTITIES+=("$line")
done < <(
  security find-identity -v -p codesigning \
  | grep '"' \
  | sed -E 's/.*"(.+)"/\1/'
)

if [ ${#IDENTITIES[@]} -eq 0 ]; then
  echo "❌ No valid code signing identities found."
  exit 1
fi

#endregion

#region List

echo ""
echo "Available Code Signing Identities:"
i=1
for identity in "${IDENTITIES[@]}"; do
  printf "%2d) %s\n" "$i" "$identity"
  i=$((i + 1))
done
printf "%2d) Custom identity\n" "$i"

#endregion

#region Choice

while true; do
    read -p "Select identity number: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Enter a number."
        continue
    fi
    if [ "$choice" -eq "$i" ]; then
        read -p "Enter custom certificate identity: " SIGN_IDENTITY
        break
    fi
    INDEX=$((choice - 1))
    if [ "$INDEX" -lt 0 ] || [ "$INDEX" -ge "${#IDENTITIES[@]}" ]; then
        echo "Number out of range."
        continue
    fi
    SIGN_IDENTITY="${IDENTITIES[$INDEX]}"
    break
done

echo ""
echo "🔏 Using identity:"
echo "   $SIGN_IDENTITY"
echo ""

#endregion

#region Signing Plugins

if [ -d "$PLUGINS_DIR" ]; then
  echo "Signing PlugIns..."

  for plugin in "$PLUGINS_DIR"/*.appex; do
    [ -e "$plugin" ] || continue
    echo "→ Signing $(basename "$plugin")"

    codesign \
      --force \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      "$plugin"
  done
else
  echo "⚠️ PlugIns folder not found, skipping plugins."
fi

#endregion

#region Signing App

echo ""
echo "Signing main app..."
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$TAURI_APP_PATH"

#endregion

#region Verification

echo ""
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$TAURI_APP_PATH"

echo ""
echo "✅ Code signing completed successfully."

#endregion

#region Bundler

# Check for arguments.
if [[ "$1" == "--bundle" ]]; then
    BUNDLE=true
else
    # Repeat question until valid answer.
    while true; do
    read -p "Do you want to bundle application into a dmg file? [Y]es/[N]o: " response
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
    echo ""
    echo "Bundling app into dmg..."

    create-dmg \
    --overwrite \
    --no-version-in-filename \
    --identity "$SIGN_IDENTITY" \
    "$TAURI_APP_PATH" \
    "$TAURI_BUNDLE_DIR"
else
    echo "Skipping bundle."
    exit 0
fi

#endregion
