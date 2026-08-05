# TimelyUNA App Store Release Checklist

## Native build

- [ ] Merge the AR Sunrise pull request.
- [ ] Pull `main` into Xcode.
- [ ] Select the TimelyUNA iOS scheme and a physical iPhone or iPad.
- [ ] Confirm the app builds with zero errors and review all warnings.
- [ ] Confirm the camera permission dialog appears and clearly explains the AR feature.
- [ ] Test Apparent Now, Actual Position, Lightline, toggles, haptics, and Baby X launch.
- [ ] Confirm the macOS build still opens its non-AR fallback.

## Safety and science

- [ ] Keep the direct-Sun safety warning visible before or during AR use.
- [ ] State that the first AR offset is educational and visually exaggerated.
- [ ] Do not describe the camera-relative markers as precision solar coordinates.
- [ ] Before claiming precision, integrate location, heading, date, atmospheric refraction, and a trusted solar ephemeris.

## App Store Connect

- [ ] Set the Apple Development Team in Signing & Capabilities.
- [ ] Confirm bundle identifier: `io.macsafedevelopersapple.TimelyUNA`.
- [ ] Increment Marketing Version and Build Number for every upload.
- [ ] Complete App Privacy answers consistently with `PrivacyInfo.xcprivacy`.
- [ ] Supply an App Store icon, iPhone screenshots, iPad screenshots if supported, description, keywords, support URL, and privacy-policy URL.
- [ ] State camera usage accurately: AR educational overlays only; no image recording or upload unless such behavior is later added.
- [ ] Archive with **Any iOS Device (arm64)**, validate the archive, then distribute to App Store Connect.
- [ ] Test through TestFlight before submitting for review.

## Accessibility

- [ ] Test VoiceOver labels and focus order.
- [ ] Test Dynamic Type where applicable.
- [ ] Test Reduce Motion and Increased Contrast.
- [ ] Confirm the science remains understandable through narration without relying entirely on sight.

## Current release boundary

The current AR Sunrise feature is suitable as an educational demonstration after device testing. It is not yet a precision astronomical instrument or spacecraft-navigation system.
