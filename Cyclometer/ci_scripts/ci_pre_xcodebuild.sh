#!/bin/zsh
# Release builds start from a `v<version>` tag (Release workflow start condition:
# Tag Changes, `v*`). The repo owns MARKETING_VERSION, set once at project level;
# this fails a tagged build whose tag disagrees with it, so what ships is what git
# says. Build numbers are Xcode Cloud's (CI_BUILD_NUMBER, applied by App Store
# Connect on upload); next build number: App Store Connect → Xcode Cloud → Settings.
set -euo pipefail

if [[ -z "${CI_TAG:-}" ]]; then
  exit 0
fi

fail() { print -u2 "error: $1"; exit 1; }

project="${0:A:h}/../Cyclometer.xcodeproj/project.xcproj"

# Xcode's General tab writes Version as a per-target override; one value keeps
# the app and widget extension in step (App Store Connect rejects a mismatch).
count=$(grep -c '"MARKETING_VERSION' "$project" || true)
(( count == 1 )) || fail "MARKETING_VERSION is set $count times in project.xcproj; set it once, in the project-level build settings."

version=$(grep -oE '"MARKETING_VERSION": "[^"]*"' "$project" | sed -E 's/.*: "(.*)"/\1/' || true)
[[ -n "$version" ]] || fail "MARKETING_VERSION must be one plain value (no [config=…] variant) in the project-level build settings."

[[ "$CI_TAG" =~ '^v[0-9]+(\.[0-9]+){0,2}$' ]] || fail "Tag '$CI_TAG' isn't v<major>[.<minor>[.<patch>]]."
[[ "${CI_TAG#v}" == "$version" ]] || fail "Tag '$CI_TAG' doesn't match MARKETING_VERSION $version. Bump the version in the project, or tag v$version."

print "Release $version (build ${CI_BUILD_NUMBER:-?}) from tag $CI_TAG"
