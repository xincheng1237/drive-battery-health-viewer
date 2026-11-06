import AppKit
import SwiftUI

/// Persistent UI density. Report text has its own independent reading size.
enum DisplaySize: String, CaseIterable, Identifiable, Sendable {
    case small, standard, large, extraLarge
    var id: String { rawValue }
    var scale: CGFloat {
        switch self {
        case .small: return 0.94
        case .standard: return 1
        case .large: return 1.16
        case .extraLarge: return 1.32
        }
    }
    var labelKey: String { "displaySize_\(rawValue)" }
}

private struct DisplaySizeKey: EnvironmentKey { static let defaultValue = DisplaySize.standard }
extension EnvironmentValues {
    var displaySize: DisplaySize {
        get { self[DisplaySizeKey.self] }
        set { self[DisplaySizeKey.self] = newValue }
    }
}

/// Native text styles are resolved before scaling. Text remains live, selectable
/// and laid out at its new size; the window is never magnified as a bitmap.
private struct InterfaceFont: ViewModifier {
    @Environment(\.displaySize) private var size
    let style: Font.TextStyle?
    let points: CGFloat?
    let weight: Font.Weight?
    let design: Font.Design
    let digits: Bool
    func body(content: Content) -> some View { content.font(resolvedFont) }
    private var resolvedFont: Font {
        let native: NSFont.TextStyle
        switch style {
        case .largeTitle: native = .largeTitle
        case .title: native = .title1
        case .title2: native = .title2
        case .title3: native = .title3
        case .headline: native = .headline
        case .subheadline: native = .subheadline
        case .callout: native = .callout
        case .footnote: native = .footnote
        case .caption: native = .caption1
        case .caption2: native = .caption2
        default: native = .body
        }
        let resolved = points ?? NSFont.preferredFont(forTextStyle: native).pointSize
        let font = Font.system(size: resolved * size.scale,
                               weight: weight ?? (style == .headline ? .semibold : .regular), design: design)
        return digits ? font.monospacedDigit() : font
    }
}

private struct InterfacePadding: ViewModifier {
    @Environment(\.displaySize) private var size
    let edges: Edge.Set
    let amount: CGFloat
    func body(content: Content) -> some View { content.padding(edges, amount * size.scale) }
}

extension View {
    func interfaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil,
                       design: Font.Design = .default, digits: Bool = false) -> some View {
        modifier(InterfaceFont(style: style, points: nil, weight: weight, design: design, digits: digits))
    }
    func interfaceFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(InterfaceFont(style: nil, points: size, weight: weight, design: .default, digits: false))
    }
    func interfacePadding(_ amount: CGFloat) -> some View { modifier(InterfacePadding(edges: .all, amount: amount)) }
    func interfacePadding(_ edges: Edge.Set, _ amount: CGFloat) -> some View {
        modifier(InterfacePadding(edges: edges, amount: amount))
    }
}

/// At most two aligned columns, collapsing to one at a readable field width.
/// Width proposals are measured again after a display-size or window change.
struct DetailColumnsLayout: Layout {
    let minimumColumnWidth: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    private func metrics(width: CGFloat, subviews: Subviews) -> (Int, CGFloat, [CGFloat]) {
        let columns = width >= minimumColumnWidth * 2 + horizontalSpacing ? 2 : 1
        let columnWidth = max(0, (width - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns))
        var rows: [CGFloat] = []
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let row = index / columns
            if rows.count <= row { rows.append(height) } else { rows[row] = max(rows[row], height) }
        }
        return (columns, columnWidth, rows)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth * 2 + horizontalSpacing
        let (_, _, rows) = metrics(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * verticalSpacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, width, rows) = metrics(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for index in subviews.indices {
            if index > 0 && index % columns == 0 { y += rows[index / columns - 1] + verticalSpacing }
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * (width + horizontalSpacing), y: y),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: width, height: rows[index / columns]))
        }
    }
}
