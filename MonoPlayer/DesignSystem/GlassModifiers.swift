import SwiftUI

/// Liquid Glass на iOS 26+, материал на iOS 17–25, сплошной фон при Reduce Transparency.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    var interactive = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.Colors.bgSecondary, in: shape)
        } else {
            #if compiler(>=6.2) // Xcode 26+: SDK с Liquid Glass
            if #available(iOS 26, *) {
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            } else {
                material(content)
            }
            #else
            material(content)
            #endif
        }
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Theme.Colors.separator.opacity(0.5), lineWidth: 0.5))
    }
}

extension View {
    func glassCapsule(interactive: Bool = true) -> some View {
        modifier(GlassBackground(shape: Capsule(), interactive: interactive))
    }

    func glassBackground(in shape: some Shape, interactive: Bool = true) -> some View {
        modifier(GlassBackground(shape: shape, interactive: interactive))
    }

    /// Источник zoom-перехода (iOS 18+): обложка мини-плеера «вырастает» в Now Playing.
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransitionDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Мягкое мерцание для плейсхолдеров, пока идёт обогащение.
    func shimmer(active: Bool) -> some View {
        modifier(Shimmer(active: active))
    }
}

private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.18), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
                .allowsHitTesting(false)
                .onAppear {
                    phase = -1
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
        .clipped()
    }
}
