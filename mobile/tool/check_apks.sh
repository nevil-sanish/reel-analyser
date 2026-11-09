#!/usr/bin/env bash
# Acceptance scan: the semi APK must not contain anything of the Full-only features, and the full APK must still contain
# them (which proves the scan can find them). Usage: tool/check_apks.sh <full.apk> <semi.apk>
set -u
FULL=${1:?full apk}; SEMI=${2:?semi apk}
SDK=${ANDROID_HOME:-$HOME/development/android-sdk}
AAPT=$(ls -d "$SDK"/build-tools/*/aapt | sort -V | tail -1)

# Strings that only the Full build may contain.
TERMS=(search/commits recentAcSubmissionList codeforces "Daily goals" "Reel blocker" "Set up Insights"
  blockSave punishSet detectionConsent setCapture appUsage seenItems ReelCounterService BlockActivity
  PACKAGE_USAGE_STATS REQUEST_INSTALL_PACKAGES POST_NOTIFICATIONS BIND_ACCESSIBILITY_SERVICE)

dump() { # apk -> one text blob of everything searchable
  local apk=$1 d; d=$(mktemp -d)
  unzip -q -o "$apk" -d "$d"
  {
    for f in "$d"/classes*.dex "$d"/lib/*/libapp.so "$d"/lib/*/libflutter.so; do [ -f "$f" ] && strings -n 6 "$f"; done
    "$AAPT" dump xmltree "$apk" AndroidManifest.xml
    "$AAPT" dump permissions "$apk"
    # resources.arsc and the xml/ folder hold labels, strings and the accessibility config
    strings -n 6 "$d"/resources.arsc 2>/dev/null
    for f in "$d"/res/xml/*.xml; do [ -f "$f" ] && strings -n 4 "$f"; done
  }
  rm -rf "$d"
}

full_txt=$(dump "$FULL"); semi_txt=$(dump "$SEMI")
bad=0
for t in "${TERMS[@]}"; do
  s=$(grep -c -F -- "$t" <<<"$semi_txt"); f=$(grep -c -F -- "$t" <<<"$full_txt")
  if [ "$s" -ne 0 ]; then echo "FAIL  semi contains: $t ($s lines)"; bad=1; fi
  if [ "$f" -eq 0 ]; then echo "FAIL  full is missing: $t (the scan cannot see it)"; bad=1; fi
done
echo "--- semi permissions"; "$AAPT" dump permissions "$SEMI" | grep -E "uses-permission" | sed 's/.*name=//' | sort
[ $bad -eq 0 ] && echo "OK: semi has none of ${#TERMS[@]} Full-only markers; full has all of them" || echo "SCAN FAILED"
exit $bad
