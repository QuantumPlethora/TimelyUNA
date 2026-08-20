# TimelyUNA App Store Release Checklist

## Canonical source

- [ ] Pull the latest `main` branch into one clean checkout.
- [ ] Confirm `git status -sb` is clean before opening Xcode.
- [ ] Open that checkout's `TimelyUNA.xcodeproj`; do not open an archived prototype or fallback copy.
- [ ] Confirm the Xcode scheme is `TimelyUNA` and the display name is `TimelyUNA`.

## Native build

- [ ] Select a physical iPhone or iPad and confirm the app builds with zero errors.
- [ ] Build the `TimelyUNA` scheme for macOS and an iOS Simulator.
- [ ] Review all build warnings.
- [ ] Confirm the camera permission dialog accurately explains the educational AR feature.
- [ ] Test Apparent Now, Actual Now, LightLine, toggles, medium launch haptics, and Beauteous Maximus.
- [ ] Confirm xSky Jump controls remain reachable and Earth/Mars surface views render correctly.
- [ ] Confirm the macOS build still opens its non-AR fallback.

## Safety and science

- [ ] Keep the direct-Sun safety warning visible before or during AR use.
- [ ] State that educational magnification is visual and not literal sky separation.
- [ ] Do not describe camera-relative markers as precision solar coordinates.
- [ ] Before claiming precision, integrate location, heading, date, atmospheric refraction, and a trusted solar ephemeris.

## App Store Connect

- [ ] Set the Apple Development Team in Signing & Capabilities.
- [ ] Confirm bundle identifier: `io.macsafedevelopersapple.TimelyUNA`.
- [ ] Increment Marketing Version and Build Number for every upload.
- [ ] Complete App Privacy answers consistently with `PrivacyInfo.xcprivacy`.
- [ ] Supply the App Store icon, supported-device screenshots, description, keywords, support URL, and privacy-policy URL.
- [ ] State camera usage accurately: educational AR overlays only; no image recording or upload unless that behavior is later added.
- [ ] Archive with **Any iOS Device (arm64)**, validate the archive, then distribute to App Store Connect.
- [ ] Test through TestFlight before submitting for review.

## Accessibility

- [ ] Test VoiceOver labels and focus order.
- [ ] Test Dynamic Type where applicable.
- [ ] Test Reduce Motion and Increased Contrast.
- [ ] Confirm the science remains understandable through narration without relying entirely on sight.

## Current release boundary

TimelyUNA is an educational visualization. Device-test every hardware-dependent feature before release; it is not a precision astronomical instrument or spacecraft-navigation system.
