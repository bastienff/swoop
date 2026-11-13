import SwiftUI

/// A row of picture tiles for a multiple-choice setting: a small illustration of each option with its name
/// below; the selected one gets an accent border. Illustrations are vector (drawn below), so they stay sharp
/// and follow light/dark mode.
struct VisualPicker<Value: Hashable, Thumbnail: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @ViewBuilder let thumbnail: (Value) -> Thumbnail

    /// Illustrations are drawn on a 128×80 canvas and shown at 75% (96×60).
    static var drawingSize: CGSize { CGSize(width: 128, height: 80) }
    static var scale: CGFloat { 0.75 }
    static var tileSize: CGSize { CGSize(width: drawingSize.width * scale, height: drawingSize.height * scale) }
    /// Same column width for every option (tile + label), so rows of different pickers line up.
    static var columnWidth: CGFloat { 118 }

    var body: some View {
        // Compact group with an even gap; the row places it on the right, next to its title.
        HStack(alignment: .top, spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    VStack(spacing: 7) {
                        thumbnail(option)
                            .frame(width: Self.drawingSize.width, height: Self.drawingSize.height)
                            .scaleEffect(Self.scale)
                            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.14),
                                                  lineWidth: selected ? 2.5 : 1))
                            .shadow(color: .black.opacity(selected ? 0.18 : 0.08), radius: selected ? 6 : 3, y: 2)
                        Text(label(option))
                            .font(.callout)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .frame(width: Self.columnWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// MARK: - Illustrations

/// Shared look for the thumbnails: a wallpaper, a mini Swoop panel, and app "icons".
private enum Mini {
    static let iconColors: [Color] = [
        Color(red: 0.98, green: 0.45, blue: 0.20), Color(red: 0.16, green: 0.52, blue: 0.95),
        Color(red: 0.74, green: 0.77, blue: 0.86), Color(red: 0.20, green: 0.70, blue: 0.40),
        Color(red: 0.62, green: 0.40, blue: 0.95), Color(red: 0.95, green: 0.28, blue: 0.30),
        Color(red: 0.98, green: 0.78, blue: 0.20), Color(red: 0.25, green: 0.25, blue: 0.32),
    ]

    static func wallpaper(dark: Bool) -> LinearGradient {
        dark
            ? LinearGradient(colors: [Color(red: 0.30, green: 0.27, blue: 0.58), Color(red: 0.08, green: 0.08, blue: 0.18)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.86, green: 0.84, blue: 0.98), Color(red: 0.70, green: 0.76, blue: 0.95)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func panelFill(dark: Bool) -> Color { dark ? Color(white: 0.13).opacity(0.92) : Color.white.opacity(0.88) }
    static func ink(dark: Bool, _ opacity: Double) -> Color { (dark ? Color.white : Color.black).opacity(opacity) }

    static func icon(_ i: Int, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(iconColors[i % iconColors.count])
            .frame(width: size, height: size)
    }

    static func searchBar(dark: Bool, width: CGFloat) -> some View {
        Capsule().fill(ink(dark: dark, 0.10)).frame(width: width, height: 5)
    }
}

/// A mini panel (as in the switcher) on a wallpaper.
private struct MiniPanel<Content: View>: View {
    var dark: Bool
    var size = CGSize(width: 96, height: 60)
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Mini.wallpaper(dark: dark)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Mini.panelFill(dark: dark))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Mini.ink(dark: dark, 0.12), lineWidth: 0.5))
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            content.frame(width: size.width, height: size.height)
        }
    }
}

/// Layout: grid, compact list, comfortable list.
struct LayoutThumbnail: View {
    let layout: PanelLayout
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        MiniPanel(dark: dark) {
            VStack(spacing: 5) {
                Mini.searchBar(dark: dark, width: layout == .grid ? 38 : 80)
                switch layout {
                case .grid:
                    VStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { r in
                            HStack(spacing: 6) {
                                ForEach(0..<4, id: \.self) { c in
                                    Mini.icon(r * 4 + c, size: 12)
                                        .padding(2)
                                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(r == 0 && c == 0 ? Mini.ink(dark: dark, 0.16) : .clear))
                                }
                            }
                        }
                    }
                case .compactList:
                    VStack(spacing: 1.5) {
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 4) {
                                Mini.icon(i, size: 5.5)
                                Capsule().fill(Mini.ink(dark: dark, 0.55)).frame(width: 14, height: 2)
                                Capsule().fill(Mini.ink(dark: dark, 0.25)).frame(width: CGFloat([34, 26, 40, 22, 30][i]), height: 2)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 4)
                            .frame(height: 7)
                            .background(RoundedRectangle(cornerRadius: 2.5).fill(i == 1 ? Mini.ink(dark: dark, 0.16) : .clear))
                        }
                    }
                    .padding(.horizontal, 6)
                case .comfortableList:
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            HStack(spacing: 5) {
                                Mini.icon(i + 1, size: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Capsule().fill(Mini.ink(dark: dark, 0.6)).frame(width: CGFloat([38, 30, 44][i]), height: 2.5)
                                    Capsule().fill(Mini.ink(dark: dark, 0.25)).frame(width: CGFloat([22, 28, 18][i]), height: 2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 5)
                            .frame(height: 12)
                            .background(RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Mini.ink(dark: dark, 0.16) : .clear))
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
    }
}

/// Appearance: system (half light, half dark), light, dark.
struct AppearanceThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        switch mode {
        case .light: grid(dark: false)
        case .dark: grid(dark: true)
        case .system:
            ZStack {
                grid(dark: false)
                grid(dark: true).mask(DiagonalHalf())
            }
        }
    }

    private func grid(dark: Bool) -> some View {
        MiniPanel(dark: dark) {
            VStack(spacing: 6) {
                Mini.searchBar(dark: dark, width: 38)
                HStack(spacing: 7) { ForEach(0..<4, id: \.self) { Mini.icon($0, size: 13) } }
                HStack(spacing: 7) { ForEach(4..<7, id: \.self) { Mini.icon($0, size: 13) } }
            }
        }
    }
}

private struct DiagonalHalf: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Icon size: the same grid with smaller or larger icons.
struct IconSizeThumbnail: View {
    let size: IconSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let (side, perRow, rows): (CGFloat, Int, Int) = switch size {
        case .small: (9, 6, 3)
        case .medium: (12, 5, 2)
        case .large: (16, 4, 2)
        }
        MiniPanel(dark: dark) {
            VStack(spacing: side * 0.45) {
                Mini.searchBar(dark: dark, width: 38)
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: side * 0.45) {
                        ForEach(0..<perRow, id: \.self) { c in Mini.icon(r * perRow + c, size: side) }
                    }
                }
            }
        }
    }
}

/// Position mode for the segmented control (backed by `AppSettings.panelDraggable`).
enum PanelPositionMode: String, CaseIterable, Hashable {
    case centered, draggable
    var label: String { self == .centered ? "Centered" : "Draggable" }
}
