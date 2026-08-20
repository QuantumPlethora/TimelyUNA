#!/usr/bin/env bash
# Fails unless the TimelyUNA canonical product contract holds.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

icon="TimelyUNA/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
backdrop="TimelyUNA/Resources/Assets.xcassets/TimelyUNATransitionBackdrop.imageset/TimelyUNA-Transition-Backdrop.jpeg"
expected_icon="82362197e863b747273af07e3611caaf6721a1c1"
expected_backdrop="d33706cb77f48d00619c5808e45376d2634767d6"

[[ -f "$icon" ]] || fail "missing approved app icon: $icon"
[[ -f "$backdrop" ]] || fail "missing approved transition backdrop: $backdrop"

icon_hash="$(git hash-object "$icon")"
backdrop_hash="$(git hash-object "$backdrop")"
[[ "$icon_hash" == "$expected_icon" ]] || fail "AppIcon.png hash $icon_hash != $expected_icon"
[[ "$backdrop_hash" == "$expected_backdrop" ]] || fail "TimelyUNA-Transition-Backdrop.jpeg hash $backdrop_hash != $expected_backdrop"

grep -q 'static let productDisplayName = "TimelyUNA"' TimelyUNA/Theme/Brand.swift \
  || fail "Brand.productDisplayName is not TimelyUNA"

grep -q 'static let tagline = "The Sun is late to its own Dawn."' TimelyUNA/Theme/Brand.swift \
  || fail "Brand.tagline is not exactly “The Sun is late to its own Dawn.”"

grep -q 'INFOPLIST_KEY_CFBundleDisplayName = TimelyUNA;' TimelyUNA.xcodeproj/project.pbxproj \
  || fail "CFBundleDisplayName is not TimelyUNA"
grep -q 'INFOPLIST_KEY_CFBundleName = TimelyUNA;' TimelyUNA.xcodeproj/project.pbxproj \
  || fail "CFBundleName is not TimelyUNA"
grep -q 'PRODUCT_NAME = TimelyUNA;' TimelyUNA.xcodeproj/project.pbxproj \
  || fail "PRODUCT_NAME is not TimelyUNA"

grep -q 'Text(Brand.productDisplayName)' TimelyUNA/Views/StartupTransitionView.swift \
  || fail "StartupTransitionView does not use Brand.productDisplayName"

grep -q 'Image("TimelyUNATransitionBackdrop")' TimelyUNA/Views/CrystalTabHost.swift \
  || fail "CrystalTabHost does not reference TimelyUNATransitionBackdrop"

grep -q 'TODAY’S ALMANAC' TimelyUNA/Views/TrueHorizonView.swift \
  || fail "almanac heading TODAY’S ALMANAC is missing"

grep -Fq 'The Sun and Moon each span about half a degree in the sky, so they look nearly the same size.' \
  TimelyUNA/Views/TrueHorizonView.swift \
  || fail "approved almanac fact is missing"

grep -q 'Text(Brand.tagline)' TimelyUNA/Views/TrueHorizonView.swift \
  || fail "TrueHorizonView does not use Brand.tagline for the Horizon heading"

for file in TimelyUNA/Theme/Brand.swift TimelyUNA/Views/TrueHorizonView.swift; do
  if grep -E -q 'Because the Sun is always late|always late to its own Dawn|late to its own horizon|from our perspective' "$file"; then
    fail "superseded Horizon sentence still present in $file"
  fi
done

echo "PASS: canonical product contract"
