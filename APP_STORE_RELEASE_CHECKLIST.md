# TimelyUNA App Store Release Checklist

## Canonical source

- [ ] Pull the latest `main` branch into one clean checkout.
- [ ] Confirm `git status -sb` is clean before opening Xcode.
- [ ] Open that checkout's `TimelyUNA.xcodeproj`; do not open an archived prototype or fallback copy.
- [ ] Confirm the Xcode scheme is `TimelyUNA` and the display name is `TimelyUNA`.
- [ ] Run `scripts/verify_canonical_product.sh` and require a pass.

## Identity, icon, backdrop, almanac, and wording

- [ ] `Brand.productDisplayName` is `TimelyUNA`.
- [ ] `INFOPLIST_KEY_CFBundleDisplayName`, `INFOPLIST_KEY_CFBundleName`, and `PRODUCT_NAME` are `TimelyUNA`.
- [ ] Opening identity is QuantumRootz → A QuantumRootz Studio → TimelyUNA → Light-Time Engine → Congruent with the Ancestors of the Cosmos.
- [ ] Opening product title and installed app name do not say “True Horizon.”
- [ ] `StartupTransitionView` shows `Brand.productDisplayName`.
- [ ] App icon `AppIcon.png` Git blob hash is `82362197e863b747273af07e3611caaf6721a1c1`. Do not redraw, crop, recolor, replace, rename, or recompress it.
- [ ] Transition backdrop `TimelyUNA-Transition-Backdrop.jpeg` Git blob hash is `d33706cb77f48d00619c5808e45376d2634767d6`. Do not redraw, crop, recolor, replace, rename, or recompress it.
- [ ] `CrystalTabHost` uses `Image("TimelyUNATransitionBackdrop")` and waits until outgoing shards finish before revealing the destination.
- [ ] Horizon start screen shows a `TODAY’S ALMANAC` card as the first content beneath persistent top chrome.
- [ ] Almanac includes the approved fact: “The Sun and Moon each span about half a degree in the sky, so they look nearly the same size.”
- [ ] `Brand.tagline` is exactly “The Sun is late to its own Dawn.” and that sentence is the prominent Horizon heading.
- [ ] Brand.swift and TrueHorizonView.swift do not contain superseded Horizon wording (“Because”, “always”, “own horizon”, or extra qualifiers).

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
