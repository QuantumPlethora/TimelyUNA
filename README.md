# TimelyUNA — Light-Time Sextant

TimelyUNA is a modern-day sextant that navigates the cosmos using light-time. This repository contains:

1. **Native SwiftUI app** (iOS, iPadOS, macOS) ready for Apple Developer / TestFlight / App Store workflows  
2. **Static HTML proof of concept** (`index.html`) for the original browser demo  

**Creator:** Craig (QuantumCentz)  
**Domain:** [macsafedevelopersapple.io](https://macsafedevelopersapple.io)

---

## Native App (SwiftUI)

### Open & run

```bash
open TimelyUNA.xcodeproj
```

In Xcode:

1. Select the **TimelyUNA** scheme  
2. Choose an **iPhone / iPad simulator**, a physical device, or **My Mac**  
3. Set your **Team** under *Signing & Capabilities* (Apple Developer account required for device + distribution)  
4. Press **Run** (⌘R)

### Build from CLI

```bash
# iOS Simulator
xcodebuild -project TimelyUNA.xcodeproj -scheme TimelyUNA \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -configuration Debug build

# macOS
xcodebuild -project TimelyUNA.xcodeproj -scheme TimelyUNA \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug build
```

### Features (ported from the HTML demo)

| Tab | Content |
|-----|---------|
| **Labyrinth** | Moment-in-time picker, interactive **Photon Labyrinth** (EARTH → PHOTONS → APPARENT → ACTUAL), Baby X rocket; **ARKit/RealityKit** launch on device |
| **Sextant** | Apparent vs actual Sun canvas, 8m 19s light-delay explanation, Baby SPCX rocket to the *true* position |
| **Chronos** | Quantum jump to 65M ly, quantum telescope → artistic Cretaceous / dinosaur scene |
| **About** | Project story, constants, system share sheet |

Visual language matches the papyrus / gold / deep-space HTML demo (serif typography, ancient borders, canvas simulations).

### Project layout

```
TimelyUNA.xcodeproj          # Xcode project + shared scheme
TimelyUNA/
  TimelyUNAApp.swift         # @main entry
  Models/                    # Light-time constants + simulation state
  Theme/                     # Papyrus-inspired palette
  Views/                     # Labyrinth, AR, Sextant, Chronos, About, canvases
  Resources/
    Assets.xcassets          # App icon + accent color
    PrivacyInfo.xcprivacy    # Required privacy manifest (no tracking / no sensitive APIs)
  TimelyUNA.entitlements     # App Sandbox (macOS)
index.html                   # Public web demo (GitHub Pages)
CNAME                        # GitHub Pages custom domain
```

### Identity & targets

| Setting | Value |
|---------|--------|
| Bundle ID | `io.macsafedevelopersapple.TimelyUNA` |
| Display name | TimelyUNA |
| Marketing version | 1.0.0 |
| Platforms | iOS 17+, iPadOS 17+, macOS 14+ |
| Category | Education |
| Privacy | Offline educational simulation; no analytics, no tracking, no network requirement |

---

## App Store / TestFlight submission checklist

1. **Apple Developer Program** membership active  
2. In Xcode → *Signing & Capabilities*: select your **Team**; leave Automatic signing on  
3. Confirm **Bundle Identifier** is unique on your account (change if already taken)  
4. Replace or refine **App Icon** in `Assets.xcassets` if desired (1024×1024 included)  
5. **Product → Archive** (destination: Any iOS Device / Any Mac)  
6. **Distribute App** → App Store Connect  
7. In [App Store Connect](https://appstoreconnect.apple.com):  
   - Create the app record (name, bundle ID, SKU)  
   - Privacy nutrition labels: **Data Not Collected** (current build)  
   - Screenshots for required device sizes  
   - Age rating (educational / cartoon dinosaurs → typically 4+)  
   - Description notes that Chronos Mode is a **thought experiment / artistic interpretation**, not scientific instrumentation  
8. Submit for **TestFlight** internal testing, then external / App Review  

Optional later: App Clip, visionOS, ARKit sky overlay, real ephemeris (JPL Horizons).

---

## HTML Version

Static proof of concept — open `index.html` in a browser, serve the folder, or publish via GitHub Pages (`CNAME` → `macsafedevelopersapple.io`).

No build step. Uses browser-native HTML, CSS, JavaScript, Canvas, and Tailwind CDN.

---

## Status

- ✅ HTML demo  
- ✅ Native SwiftUI multiplatform app (iOS / iPadOS / macOS)  
- ✅ Privacy manifest + sandbox entitlements  
- ⏳ TestFlight / App Store (requires your Developer Team signing)  
- 🔮 Future: ARKit light-time sextant, real ephemerides, visionOS  

---

Made with curiosity. The light you see is already history.
