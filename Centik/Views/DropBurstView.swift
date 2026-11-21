import Lottie
import SwiftUI

/// A short landing flourish. Lottie plays the bundled burst; if the animation
/// cannot be decoded, a SwiftUI ring still marks the drop.
struct DropBurstView: View {
    var token: Int

    var body: some View {
        ZStack {
            if token > 0, let animation = LottieAnimation.named("DropLand") {
                LottieView(animation: animation)
                    .playing(loopMode: .playOnce)
                    .animationSpeed(1.15)
                    .resizable()
            } else if token > 0 {
                FallbackRing()
            }
        }
        .id(token)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FallbackRing: View {
    @State private var grown = false

    var body: some View {
        Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            .frame(width: grown ? 200 : 36, height: grown ? 72 : 14)
            .opacity(grown ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) {
                    grown = true
                }
            }
    }
}
