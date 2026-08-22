# True Horizon for Xcode

One SwiftUI codebase for macOS 14+, iOS 17+, and iPadOS 17+. **True Horizon** is the product name and Papyrus is used throughout the interface.

## Open on your Mac

### Fastest: generate the Xcode project

1. Install Xcode from the Mac App Store and open it once.
2. Install XcodeGen: `brew install xcodegen`
3. In Terminal, open this folder and run: `xcodegen generate`
4. Open `TrueHorizon.xcodeproj`.
5. Select the **TrueHorizon-iOS** or **TrueHorizon-macOS** target → **Signing & Capabilities** → choose your Apple development team.
6. Choose **My Mac**, an iPhone/iPad simulator, or a connected device and press Run.

### Without XcodeGen

Create a new Xcode **Multiplatform App** named `TrueHorizon`, delete its generated Swift files, drag the `TrueHorizon` folder into the project with “Copy items if needed,” then add Location capability/usage text. The supplied files contain no third-party runtime dependencies.

## Real calculations

`SolarEngine.swift` calculates geocentric solar coordinates, apparent altitude/azimuth, Earth–Sun distance, live photon travel time, refraction, local sunrise, and the light-time-corrected true position. It works offline after Core Location supplies coordinates.

The “true Sun” is evaluated at `now + photon travel time`, which displays where the Sun has progressed to while the photons currently reaching the observer were in flight.

## Included first-build features

- Live location and solar position
- Apparent-vs-true Sun display
- Daily launch ritual and local streak storage
- True vs visible sunrise time
- Universal navigation for Mac, iPhone, and iPad
- Epoch collection foundation
- Deep-time postcard foundation

## Recommended next engineering passes

- Add unit tests against JPL Horizons reference dates
- Use SwiftData/iCloud for cross-device streaks and collections
- Add SceneKit/RealityKit sky rendering and device orientation
- Add planets, Moon, constellation layers, rare alignment puzzles, sharing images, notifications, and scientifically reconstructed paleoskies
