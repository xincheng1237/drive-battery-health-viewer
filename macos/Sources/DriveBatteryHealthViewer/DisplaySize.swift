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

/// Keeps the gauge, heading and details mounted as the window resizes. The
/// details first clear the gauge vertically, then widen into the space below it.
struct OverviewCardLayout: Layout {
    let scale: CGFloat
    typealias Cache = (width: CGFloat, frames: [CGRect])?

    func makeCache(subviews: Subviews) -> Cache { nil }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let gauge = subviews[0].sizeThatFits(.unspecified)
        let gap = 14 * scale
        let wideInset = gauge.width + 24 * scale
        let transitionWidth = 124 * scale
        let start = max(515, wideInset + 348 * scale) + transitionWidth
        let compactness = min(1, max(0, (start - width) / transitionWidth))
        let clearancePoint = 0.52
        let lower = eased(compactness / clearancePoint)
        let widen = eased((compactness - clearancePoint) / (1 - clearancePoint))
        let headerX = wideInset - 8 * scale * lower
        let headerWidth = max(0, width - headerX)
        let header = subviews[1].sizeThatFits(ProposedViewSize(width: headerWidth, height: nil))
        let headerY = max(0, (gauge.height - header.height) / 2) * lower
        let headerBottom = headerY + header.height
        // Begin closing the horizontal gap while the details move down. They
        // can pass the gauge only after clearing it, without a pause between axes.
        let sideInset = wideInset - 8 * scale * eased(compactness / 0.75)
        let detailsX = sideInset * (1 - widen)
        let detailsY = headerBottom + gap + max(0, gauge.height - headerBottom) * lower
        let detailsWidth = max(0, width - detailsX)
        let details = subviews[2].sizeThatFits(ProposedViewSize(width: detailsWidth, height: nil))
        return [
            CGRect(origin: .zero, size: gauge),
            CGRect(x: headerX, y: headerY, width: headerWidth, height: header.height),
            CGRect(x: detailsX, y: detailsY, width: detailsWidth, height: details.height)
        ]
    }

    private func eased(_ value: CGFloat) -> CGFloat {
        let progress = min(1, max(0, value))
        return progress * progress * (3 - 2 * progress)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 600 * scale
        let frames = frames(width: width, subviews: subviews)
        cache = (width, frames)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let placements = cache.flatMap { $0.width == bounds.width ? $0.frames : nil }
            ?? frames(width: bounds.width, subviews: subviews)
        cache = nil
        for (view, frame) in zip(subviews, placements) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: nil))
        }
    }
}

/// At most two aligned columns, collapsing to one at a readable field width.
/// Width proposals are measured again after a display-size or window change.
struct DetailColumnsLayout: Layout {
    struct Measurement {
        let width: CGFloat
        let columns: Int
        let columnWidth: CGFloat
        let rows: [CGFloat]
    }
    struct Cache {
        let idealSizes: [CGSize]
        var measurement: Measurement?
    }

    let minimumColumnWidth: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func makeCache(subviews: Subviews) -> Cache {
        Cache(idealSizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    private func fieldProposal(idealSize: CGSize, columnWidth: CGFloat) -> ProposedViewSize {
        idealSize.width <= columnWidth ? .unspecified : ProposedViewSize(width: columnWidth, height: nil)
    }

    private func measure(width: CGFloat, subviews: Subviews, idealSizes: [CGSize]) -> Measurement {
        let columns = width >= minimumColumnWidth * 2 + horizontalSpacing ? 2 : 1
        let columnWidth = max(0, (width - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns))
        var rows: [CGFloat] = []
        for index in subviews.indices {
            let ideal = idealSizes[index]
            let height = ideal.width <= columnWidth
                ? ideal.height
                : subviews[index].sizeThatFits(fieldProposal(idealSize: ideal, columnWidth: columnWidth)).height
            let row = index / columns
            if rows.count <= row { rows.append(height) } else { rows[row] = max(rows[row], height) }
        }
        return Measurement(width: width, columns: columns, columnWidth: columnWidth, rows: rows)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth * 2 + horizontalSpacing
        let measurement = measure(width: width, subviews: subviews, idealSizes: cache.idealSizes)
        cache.measurement = measurement
        let rows = measurement.rows
        return CGSize(width: width, height: rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * verticalSpacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let measurement = cache.measurement.flatMap { $0.width == bounds.width ? $0 : nil }
            ?? measure(width: bounds.width, subviews: subviews, idealSizes: cache.idealSizes)
        cache.measurement = nil
        let columns = measurement.columns
        let width = measurement.columnWidth
        let rows = measurement.rows
        var y = bounds.minY
        for index in subviews.indices {
            if index > 0 && index % columns == 0 { y += rows[index / columns - 1] + verticalSpacing }
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * (width + horizontalSpacing), y: y),
                                 anchor: .topLeading, proposal: fieldProposal(idealSize: cache.idealSizes[index], columnWidth: width))
        }
    }
}
