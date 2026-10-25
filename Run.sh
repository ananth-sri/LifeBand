#!/bin/bash
# Run.sh
# Detects every currently connected device (wired or wireless, any number)
# and opens a SEPARATE Terminal.app window running `flutter run` for each
# one.
#
# WHY SEPARATE WINDOWS, NOT ONE TERMINAL: `flutter run -d all` (and a
# comma-separated -d list, which isn't actually valid syntax) both proved
# unreliable for wireless devices in testing — wireless devices take a few
# extra seconds to finish network discovery, and Flutter's -d all only
# grabs whatever's already discovered the instant it starts, silently
# dropping the wireless one. This is a real limitation in Flutter's own
# tooling, not something fixable from a script. Separate windows, each
# explicitly targeting one confirmed device ID, is the reliable option.

PROJECT_DIR="$HOME/Developer/triton_app_v2"
cd "$PROJECT_DIR" || { echo "Could not find project at $PROJECT_DIR"; exit 1; }

echo "Scanning for connected devices..."
DEVICE_LIST="$(flutter devices)"
echo "$DEVICE_LIST"
echo ""

# Parse device IDs, skipping desktop/web targets (macOS, Chrome).
DEVICE_IDS=$(echo "$DEVICE_LIST" \
  | grep "•" \
  | grep -v "(desktop)" \
  | grep -v "(web)" \
  | awk -F'•' '{print $2}' \
  | xargs -n1 echo)

if [ -z "$DEVICE_IDS" ]; then
  echo "No mobile devices found. Make sure your phone(s) are connected/paired and try again."
  exit 1
fi

COUNT=$(echo "$DEVICE_IDS" | wc -l | xargs)
echo "Found $COUNT device(s). Opening a Terminal window for each..."
echo ""

while IFS= read -r ID; do
  echo "Launching on device: $ID"
  osascript -e "tell application \"Terminal\" to do script \"cd '$PROJECT_DIR' && flutter run -d $ID\""
done <<< "$DEVICE_IDS"

echo ""
echo "Done - check the new Terminal window(s) for build progress."