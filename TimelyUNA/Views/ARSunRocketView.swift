import SwiftUI

#if os(iOS)
import UIKit
import RealityKit
import ARKit

/// Full-screen AR session: sun proxy + Baby X rocket with tap-to-launch.
struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if ARWorldTrackingConfiguration.isSupported {
                ARViewContainer(selectedDate: selectedDate)
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
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding()
            }
            .accessibilityLabel("Close AR")
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                Text("Point your phone at the sky")
                    .font(.custom("Papyrus", size: 22, relativeTo: .title3).weight(.bold))
                Text("Tap to launch Baby X toward the Sun")
                    .font(.custom("Papyrus", size: 18, relativeTo: .body))
                Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(TimelyUNATheme.accent)
            }
            .foregroundStyle(TimelyUNATheme.papyrus)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let selectedDate: Date

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            // Optional; ignore if unsupported
        }
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        context.coordinator.setupScene(in: arView)
        context.coordinator.selectedDate = selectedDate

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.launchRocket(_:))
        )
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.selectedDate = selectedDate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var rocket: ModelEntity?
        var sunEntity: ModelEntity?
        var selectedDate: Date = Date()
        private var hasLaunched = false

        func setupScene(in arView: ARView) {
            // Place content ~2m in front of the camera (sky / outdoor framing).
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0.2, -2.0))

            // Sun proxy
            let sunMesh = MeshResource.generateSphere(radius: 0.28)
            var sunMaterial = SimpleMaterial()
            sunMaterial.color = .init(tint: UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1))
            sunMaterial.metallic = 0.35
            sunMaterial.roughness = 0.25
            let sun = ModelEntity(mesh: sunMesh, materials: [sunMaterial])
            sun.position = [0.35, 0.55, -0.4]
            sun.name = "Sun"
            sunEntity = sun
            anchor.addChild(sun)

            // Soft glow shell
            let glowMesh = MeshResource.generateSphere(radius: 0.38)
            var glowMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.25))
            let glow = ModelEntity(mesh: glowMesh, materials: [glowMaterial])
            sun.addChild(glow)

            // Baby X Rocket
            let rocketMesh = MeshResource.generateBox(size: [0.08, 0.22, 0.08], cornerRadius: 0.02)
            var rocketMaterial = SimpleMaterial()
            rocketMaterial.color = .init(tint: UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1))
            rocketMaterial.metallic = 0.15
            let rocketEntity = ModelEntity(mesh: rocketMesh, materials: [rocketMaterial])
            rocketEntity.position = [0, -0.45, 0.15]
            rocketEntity.name = "BabyXRocket"
            // Point rocket roughly toward the sun
            rocketEntity.look(at: sun.position, from: rocketEntity.position, relativeTo: anchor)
            rocket = rocketEntity
            anchor.addChild(rocketEntity)

            // Nose tip accent
            let nose = ModelEntity(
                mesh: .generateSphere(radius: 0.035),
                materials: [SimpleMaterial(color: .white, isMetallic: true)]
            )
            nose.position = [0, 0.14, 0]
            rocketEntity.addChild(nose)

            arView.scene.addAnchor(anchor)
            hasLaunched = false
        }

        @objc func launchRocket(_ sender: UITapGestureRecognizer) {
            guard let rocket, let sunEntity, !hasLaunched else { return }
            hasLaunched = true

            // Fly toward (and slightly past) the sun over 4 seconds.
            let target = sunEntity.position(relativeTo: nil) + SIMD3<Float>(0, 0.15, -0.2)
            var transform = rocket.transform
            transform.translation = target
            rocket.move(to: transform, relativeTo: nil, duration: 4.0, timingFunction: .easeInOut)

            // After arrival, pulse the sun slightly
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak sunEntity] in
                guard let sunEntity else { return }
                var t = sunEntity.transform
                t.scale = SIMD3<Float>(repeating: 1.2)
                sunEntity.move(to: t, relativeTo: sunEntity.parent, duration: 0.35)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    var back = sunEntity.transform
                    back.scale = SIMD3<Float>(repeating: 1.0)
                    sunEntity.move(to: back, relativeTo: sunEntity.parent, duration: 0.35)
                }
            }
        }
    }
}

#Preview {
    ARSunRocketView(selectedDate: Date())
}

#else

/// Non-iOS placeholder so the module still compiles on macOS.
struct ARSunRocketView: View {
    let selectedDate: Date

    var body: some View {
        ContentUnavailableView(
            "AR on iPhone & iPad",
            systemImage: "arkit",
            description: Text("Open TimelyUNA on a device with ARKit to launch the Baby X rocket at \(selectedDate.formatted(date: .abbreviated, time: .shortened)).")
        )
    }
}

#endif
