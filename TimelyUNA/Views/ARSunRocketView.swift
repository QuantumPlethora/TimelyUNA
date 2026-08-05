import SwiftUI

#if os(iOS)
import UIKit
import RealityKit
import ARKit

/// Full-screen TimelyUNA AR experience.
///
/// This first production step places an educational, camera-relative sunrise model
/// into the real world. It shows:
/// - Apparent Now
/// - Actual Position
/// - the Lightline between them
/// - an optional Baby X launch toward Actual Position
///
/// The overlay is intentionally labeled as educational. A later precision build
/// should replace the demo offset with coordinates from Core Location plus a
/// trusted solar ephemeris and atmospheric-refraction model.
struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var showActualPosition = true
    @State private var showLightline = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if ARWorldTrackingConfiguration.isSupported {
                ARSunriseContainer(
                    selectedDate: selectedDate,
                    showActualPosition: showActualPosition,
                    showLightline: showLightline
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "AR Unavailable",
                    systemImage: "camera.fill",
                    description: Text("This device does not support world-tracking AR.")
                )
                .background(TimelyUNATheme.background)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding()
            }
            .accessibilityLabel("Close TimelyUNA AR")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text("We do not see the universe as it is. We see it as its light arrives.")
                    .font(.custom("Papyrus", size: 19, relativeTo: .headline).weight(.bold))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Toggle("Actual Position", isOn: $showActualPosition)
                    Toggle("Lightline", isOn: $showLightline)
                }
                .font(.custom("Papyrus", size: 15, relativeTo: .body))
                .toggleStyle(.button)

                Text("Point toward the horizon. Tap the scene to launch Baby X toward Actual Position.")
                    .font(.custom("Papyrus", size: 15, relativeTo: .footnote))
                    .multilineTextAlignment(.center)

                Text("Educational overlay • \(selectedDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(TimelyUNATheme.accent)
            }
            .foregroundStyle(TimelyUNATheme.papyrus)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }
}

struct ARSunriseContainer: UIViewRepresentable {
    let selectedDate: Date
    let showActualPosition: Bool
    let showLightline: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )

        context.coordinator.setupScene(in: arView)
        context.coordinator.selectedDate = selectedDate

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.launchRocket(_:))
        )
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.selectedDate = selectedDate
        context.coordinator.setActualPositionVisible(showActualPosition)
        context.coordinator.setLightlineVisible(showLightline)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedDate = Date()

        private weak var arView: ARView?
        private var rootAnchor: AnchorEntity?
        private var apparentSun: ModelEntity?
        private var actualSun: ModelEntity?
        private var lightline: ModelEntity?
        private var rocket: ModelEntity?
        private var actualLabel: ModelEntity?
        private var lightlineLabel: ModelEntity?
        private var hasLaunched = false

        func setupScene(in arView: ARView) {
            self.arView = arView

            // Camera-relative educational placement approximately 2.5 m ahead.
            // The horizontal separation exaggerates the offset for learning.
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0.15, -2.5))
            rootAnchor = anchor

            let apparentPosition = SIMD3<Float>(-0.38, 0.38, 0)
            let actualPosition = SIMD3<Float>(0.42, 0.48, -0.08)

            let apparent = makeSun(
                radius: 0.20,
                color: UIColor(red: 0.98, green: 0.72, blue: 0.16, alpha: 0.78)
            )
            apparent.position = apparentPosition
            apparent.name = "ApparentNow"
            apparentSun = apparent
            anchor.addChild(apparent)

            let actual = makeSun(
                radius: 0.22,
                color: UIColor(red: 1.0, green: 0.91, blue: 0.35, alpha: 1.0)
            )
            actual.position = actualPosition
            actual.name = "ActualPosition"
            actualSun = actual
            anchor.addChild(actual)

            let apparentText = makeLabel("APPARENT NOW", color: .white)
            apparentText.position = apparentPosition + SIMD3<Float>(-0.18, -0.34, 0)
            anchor.addChild(apparentText)

            let actualText = makeLabel("ACTUAL POSITION", color: UIColor(red: 1, green: 0.87, blue: 0.35, alpha: 1))
            actualText.position = actualPosition + SIMD3<Float>(-0.20, -0.36, 0)
            actualLabel = actualText
            anchor.addChild(actualText)

            let line = makeLine(
                from: apparentPosition,
                to: actualPosition,
                color: UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 0.88)
            )
            lightline = line
            anchor.addChild(line)

            let middle = (apparentPosition + actualPosition) / 2
            let lineText = makeLabel("LIGHTLINE", color: UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1))
            lineText.position = middle + SIMD3<Float>(-0.10, 0.12, 0)
            lightlineLabel = lineText
            anchor.addChild(lineText)

            let rocketEntity = makeRocket()
            rocketEntity.position = SIMD3<Float>(-0.05, -0.55, 0.12)
            rocketEntity.look(
                at: actualPosition,
                from: rocketEntity.position,
                relativeTo: anchor
            )
            rocket = rocketEntity
            anchor.addChild(rocketEntity)

            arView.scene.addAnchor(anchor)
            hasLaunched = false
        }

        func setActualPositionVisible(_ visible: Bool) {
            actualSun?.isEnabled = visible
            actualLabel?.isEnabled = visible
        }

        func setLightlineVisible(_ visible: Bool) {
            lightline?.isEnabled = visible
            lightlineLabel?.isEnabled = visible
        }

        @objc func launchRocket(_ recognizer: UITapGestureRecognizer) {
            guard
                let rocket,
                let actualSun,
                let anchor = rootAnchor,
                !hasLaunched
            else { return }

            hasLaunched = true
            let target = actualSun.position(relativeTo: anchor) + SIMD3<Float>(0, 0.10, -0.06)
            var transform = rocket.transform
            transform.translation = target

            rocket.move(
                to: transform,
                relativeTo: anchor,
                duration: 3.2,
                timingFunction: .easeInOut
            )

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
                guard let self, let actualSun = self.actualSun else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                var pulse = actualSun.transform
                pulse.scale = SIMD3<Float>(repeating: 1.20)
                actualSun.move(to: pulse, relativeTo: actualSun.parent, duration: 0.28)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    var normal = actualSun.transform
                    normal.scale = SIMD3<Float>(repeating: 1.0)
                    actualSun.move(to: normal, relativeTo: actualSun.parent, duration: 0.28)
                }
            }
        }

        private func makeSun(radius: Float, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateSphere(radius: radius)
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: Float(color.cgColor.alpha)))
            let sun = ModelEntity(mesh: mesh, materials: [material])

            let glow = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.35),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.18))]
            )
            sun.addChild(glow)
            return sun
        }

        private func makeRocket() -> ModelEntity {
            let body = ModelEntity(
                mesh: .generateBox(size: [0.07, 0.22, 0.07], cornerRadius: 0.018),
                materials: [SimpleMaterial(color: .systemOrange, isMetallic: true)]
            )

            let nose = ModelEntity(
                mesh: .generateSphere(radius: 0.032),
                materials: [SimpleMaterial(color: .white, isMetallic: true)]
            )
            nose.position = [0, 0.13, 0]
            body.addChild(nose)
            return body
        }

        private func makeLabel(_ text: String, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.002,
                font: UIFont(name: "Papyrus", size: 0.12) ?? .systemFont(ofSize: 0.12),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byWordWrapping
            )
            let entity = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: color)]
            )
            entity.scale = SIMD3<Float>(repeating: 0.55)
            return entity
        }

        private func makeLine(
            from start: SIMD3<Float>,
            to end: SIMD3<Float>,
            color: UIColor
        ) -> ModelEntity {
            let vector = end - start
            let length = simd_length(vector)
            let midpoint = (start + end) / 2

            let entity = ModelEntity(
                mesh: .generateCylinder(height: length, radius: 0.012),
                materials: [UnlitMaterial(color: color)]
            )
            entity.position = midpoint
            entity.orientation = simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: simd_normalize(vector)
            )
            return entity
        }
    }
}

#Preview {
    ARSunRocketView(selectedDate: Date())
}

#else

struct ARSunRocketView: View {
    let selectedDate: Date

    var body: some View {
        ContentUnavailableView(
            "AR on iPhone & iPad",
            systemImage: "arkit",
            description: Text(
                "Open TimelyUNA on an ARKit device to reveal Apparent Now, Actual Position, and the Lightline."
            )
        )
    }
}

#endif
