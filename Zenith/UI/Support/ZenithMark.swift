import SwiftUI

/// Zenith's brand mark: two overlapping triangular "peaks" — a literal
/// zenith/summit shape — rendered as vectors so it stays crisp at any
/// size. Coordinates are normalized to a `0...1` square; callers place
/// it in whatever frame they like via `.frame(width:height:)`.
///
/// This is the native port of the old web app's
/// `components/icons/zenith-mark.tsx`. Kept in sync by hand with
/// `macos/Scripts/generate-app-icon.swift`, which rasterizes the same
/// two triangles (in white, on a brand-blue rounded square) for the app
/// icon.
struct ZenithMark: View {
    var color: Color = .accentColor

    /// Back peak, drawn first and dimmed — normalized `0...1` coordinates.
    private static let backPeak: [CGPoint] = [
        CGPoint(x: 0.21875, y: 0.71875),
        CGPoint(x: 0.40625, y: 0.3125),
        CGPoint(x: 0.59375, y: 0.71875),
    ]

    /// Front peak — taller, fully opaque, reaching the shared high point.
    private static let frontPeak: [CGPoint] = [
        CGPoint(x: 0.375, y: 0.75),
        CGPoint(x: 0.53125, y: 0.21875),
        CGPoint(x: 0.75, y: 0.75),
    ]

    var body: some View {
        Canvas { context, size in
            context.fill(Self.path(Self.backPeak, in: size), with: .color(color.opacity(0.45)))
            context.fill(Self.path(Self.frontPeak, in: size), with: .color(color))
        }
    }

    private static func path(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: points[0].x * size.width, y: points[0].y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// Zenith's brand blue (`#326bff`) — used for `AccentColor` and the
    /// mark's badge background.
    static let zenithBrand = Color(red: 0x32 / 255.0, green: 0x6b / 255.0, blue: 0xff / 255.0)
}

#Preview {
    HStack(spacing: 8) {
        ZenithMark(color: .accentColor)
            .frame(width: 16, height: 16)
            .padding(5)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        Text("zenith")
            .font(.system(.body, design: .monospaced, weight: .semibold))
    }
    .padding()
}
