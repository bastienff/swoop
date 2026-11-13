#!/usr/bin/env bash
# Prints release notes (Markdown) built from Conventional Commits since the previous release tag.
# Used by .github/workflows/release.yml when a release is published; run it locally to preview:
#
#   scripts/release_notes.sh            # unreleased changes (previous tag..HEAD)
#   scripts/release_notes.sh v1.2.0     # notes for an existing tag
#
# Sections: breaking changes (`type!:` or a `BREAKING CHANGE:` footer), feat, fix, perf. Other types
# (refactor, test, ci, docs, build, chore, style) are internal: counted, not listed. Commits that don't
# follow the convention are listed under "Other changes" so nothing user-visible is silently dropped.
set -euo pipefail

TAG="${1:-HEAD}"
REPO="${GITHUB_REPOSITORY:-bastienff/swoop}"
URL="https://github.com/$REPO"

git rev-parse -q --verify "$TAG^{commit}" >/dev/null || { echo "unknown tag or ref: $TAG" >&2; exit 1; }
# Previous release: the nearest vX.Y.Z tag before TAG (none for the first release).
PREV="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$TAG^" 2>/dev/null || true)"
RANGE="${PREV:+$PREV..}$TAG"

# One record per commit: hash \x1f subject \x1f body \x1e
git log --no-merges --reverse --format='%H%x1f%s%x1f%b%x1e' "$RANGE" | awk -v url="$URL" '
BEGIN { RS = "\x1e"; FS = "\x1f" }
{
    sub(/^\n+/, "", $1)
    hash = $1; subject = $2; body = $3
    if (hash == "") next
    short = substr(hash, 1, 7)
    if (match(subject, /^[a-z]+(\([^)]*\))?!?: /)) {
        head = substr(subject, 1, RLENGTH - 2); text = substr(subject, RLENGTH + 1)
        type = head; sub(/[(!].*/, "", type)
        breaking = (head ~ /!$/) || (body ~ /(^|\n)BREAKING[ -]CHANGE: /)
    } else {
        type = "other"; text = subject; breaking = 0
    }
    text = toupper(substr(text, 1, 1)) substr(text, 2)
    sub(/\.$/, "", text)
    item = "- " text " ([" short "](" url "/commit/" hash "))"
    if (breaking) { breaking_items = breaking_items item "\n" }
    if (type == "feat") feat = feat item "\n"
    else if (type == "fix") fix = fix item "\n"
    else if (type == "perf") perf = perf item "\n"
    else if (type == "revert" || type == "other") other = other item "\n"
    else internal++
}
function section(title, items) { if (items != "") printf "### %s\n\n%s\n", title, items }
END {
    section("⚠️ Breaking changes", breaking_items)
    section("✨ New", feat)
    section("🐛 Fixes", fix)
    section("⚡ Performance", perf)
    section("Other changes", other)
    if (feat fix perf other breaking_items == "") printf "Maintenance release.\n\n"
    if (internal > 0) printf "_Plus %d internal change%s (refactoring, tests, CI, docs)._\n\n", internal, (internal == 1 ? "" : "s")
}'

cat <<FOOTER
### Install or update

\`\`\`sh
brew install --cask bastienff/tap/swoop   # new install
brew upgrade --cask swoop                 # update
\`\`\`

Or download **Swoop.zip** below. Requires an Apple silicon Mac with macOS 14 or later.

FOOTER
if [ -n "$PREV" ]; then
    echo "**Full changelog**: [$PREV...${TAG/#HEAD/main}]($URL/compare/$PREV...${TAG/#HEAD/main})"
else
    echo "**Full changelog**: [commits]($URL/commits/${TAG/#HEAD/main})"
fi
