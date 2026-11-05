#!/bin/zsh
# Xcode Cloud only runs ci_scripts/ that sit next to the .xcodeproj.
# Trust the package macros listed in macros.json (fingerprint = pinned revision
# in Package.resolved — update both together when bumping a macro package).
set -euo pipefail
mkdir -p ~/Library/org.swift.swiftpm/security/
cp "${0:A:h}/macros.json" ~/Library/org.swift.swiftpm/security/macros.json
