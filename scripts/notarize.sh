#!/usr/bin/env bash
# Notarize a Developer ID-signed Swoop.app or .dmg with Apple and staple the ticket to it.
# Usage: scripts/notarize.sh <Swoop.app | Swoop.dmg>
# Needs an App Store Connect API key: NOTARY_KEY (path to AuthKey_XXXXXXXXXX.p8), NOTARY_KEY_ID, NOTARY_ISSUER_ID.
# Optional: NOTARY_TIMEOUT (default 30m); NOTARY_SUBMISSION_ID=<id> waits for an earlier submission of the
# same file instead of uploading it again (e.g. after a timeout: Apple keeps processing it).
set -euo pipefail
TARGET="${1:?usage: scripts/notarize.sh <Swoop.app | file.dmg>}"
: "${NOTARY_KEY:?path to the .p8 API key}" "${NOTARY_KEY_ID:?API key id}" "${NOTARY_ISSUER_ID:?API issuer id}"
AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
TIMEOUT="${NOTARY_TIMEOUT:-30m}"

if [[ -n "${NOTARY_SUBMISSION_ID:-}" ]]; then
  ID="$NOTARY_SUBMISSION_ID"
  echo "Waiting for submission ${ID}..."
  RESULT="$(xcrun notarytool wait "$ID" "${AUTH[@]}" --timeout "$TIMEOUT" --output-format json 2>&1)" || true
else
  # notarytool takes a zip, dmg or pkg; an app is sent zipped (the ticket is stapled to the app itself).
  SUBMIT="$TARGET"
  if [[ -d "$TARGET" ]]; then
    SUBMIT="$(mktemp -d)/$(basename "$TARGET").zip"
    ditto -c -k --keepParent "$TARGET" "$SUBMIT"
  fi
  echo "Notarizing $TARGET (usually a few minutes; a new account's first submissions can take hours)..."
  RESULT="$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout "$TIMEOUT" --output-format json 2>&1)" || true
  ID="$(plutil -extract id raw - <<<"$RESULT" 2>/dev/null || true)"
fi

STATUS="$(plutil -extract status raw - <<<"$RESULT" 2>/dev/null || true)"
case "$STATUS" in
  Accepted) ;;
  "In Progress"|"")
    if [[ -n "$ID" ]] && grep -q "Timeout" <<<"$RESULT"; then
      echo "error: still processing after $TIMEOUT. Apple keeps working on it; resume without re-uploading:" >&2
      echo "  NOTARY_SUBMISSION_ID=$ID scripts/notarize.sh $TARGET" >&2
    else
      echo "error: notarytool failed:" >&2
      echo "$RESULT" >&2
    fi
    exit 1 ;;
  *)
    echo "error: notarization $STATUS (submission $ID). Apple's log:" >&2
    xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
    exit 1 ;;
esac
xcrun stapler staple "$TARGET"
echo "Notarized and stapled $TARGET"
