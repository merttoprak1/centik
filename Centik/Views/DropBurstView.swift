import Lottie
import SwiftUI

/// A short landing flourish. Combines the bundled Lottie burst with a crisp
/// minimalist radial shimmer ring so every drop feels tactile and weightless.
struct DropBurstView: View {
    var token: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if token > 0, !reduceMotion {
                ShimmerWave()
                if let animation = LottieAnimation.named("DropLand") {
                    LottieView(animation: animation)
                        .playing(loopMode: .playOnce)
                        .animationSpeed(1.2)
                        .resizable()
                        .opacity(0.85)
                }
            }
        }
        .id(token)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ShimmerWave: View {
    @State private var expanded = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.75), Color.white.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: expanded ? 0.5 : 1.8
                )
                .frame(width: expanded ? 220 : 40, height: expanded ? 82 : 18)
                .opacity(expanded ? 0 : 0.85)
                .blur(radius: expanded ? 2 : 0)

            Ellipse()
                .fill(Color.white.opacity(expanded ? 0 : 0.18))
                .frame(width: expanded ? 180 : 32, height: expanded ? 48 : 12)
                .blur(radius: 14)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.52)) {
                expanded = true
            }
        }
    }
}
