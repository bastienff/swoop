#!/usr/bin/env bash
# Prints the Homebrew cask for a Swoop release. Used by .github/workflows/release.yml to update the
# tap (bastienff/homebrew-tap → Casks/swoop.rb). Usage: scripts/make_cask.sh <version> <sha256>
set -euo pipefail
VERSION="${1:?version, e.g. 1.2.0}"
SHA256="${2:?sha256 of Swoop.zip}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "bad version: $VERSION" >&2; exit 1; }
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "bad sha256: $SHA256" >&2; exit 1; }
cat <<CASK
cask "swoop" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/bastienff/swoop/releases/download/v#{version}/Swoop.zip"
  name "Swoop"
  desc "Window switcher: every window, one keystroke"
  homepage "https://github.com/bastienff/swoop"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Swoop.app"

  zap trash: [
    "~/Library/Application Support/Swoop",
    "~/Library/Preferences/com.bastienff.swoop.plist",
  ]
end
CASK
