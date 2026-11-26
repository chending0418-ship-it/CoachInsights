import SwiftUI

/// Shared surfaces for the field notebook. Media canvases and the classic board draw their own backgrounds.
enum Notebook {
    static let ink = Color(red: 39/255, green: 38/255, blue: 38/255)
    static let paper = Color(red: 1, green: 254/255, blue: 250/255)
    static let rule = Color(red: 217/255, green: 212/255, blue: 201/255)
    static let inset = Color(red: 241/255, green: 239/255, blue: 231/255)
    static let fieldGreen = Color(red: 49/255, green: 86/255, blue: 76/255)
}

extension View {
    func notebookPanel() -> some View {
        padding(14)
            .background(Notebook.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Notebook.rule) }
    }

    func notebookForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Notebook.inset.opacity(0.55))
            .environment(\.defaultMinListRowHeight, 46)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct NotebookHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NotebookToolRow: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline)
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.burgundy).background(Notebook.inset, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct LatestTrainingCard: View {
    let title: String
    let audience: String
    let date: Date
    let summary: String
    let action: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(audience, systemImage: icon)
                Spacer()
                Text(date, style: .date)
            }.font(.caption).foregroundStyle(.secondary)
            Text(title).font(.title2.bold()).foregroundStyle(Notebook.ink)
            if !summary.isEmpty { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            HStack { Text(action); Spacer(); Image(systemName: "arrow.right") }
                .font(.caption.bold()).foregroundStyle(Theme.burgundy)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Notebook.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Notebook.rule) }
    }
}

/// Two reading regions stay in document order when the window becomes narrow.
struct NotebookColumns: Layout {
    var minimumWidth: CGFloat = 720
    var leadingFraction: CGFloat = 0.64
    var spacing: CGFloat = 20

    private func regions(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let wide = width >= minimumWidth && subviews.count == 2
        var y: CGFloat = 0
        return subviews.enumerated().map { index, view in
            let firstWidth = (width - spacing) * leadingFraction
            let column = wide ? (index == 0 ? firstWidth : width - spacing - firstWidth) : width
            let size = view.sizeThatFits(ProposedViewSize(width: column, height: nil))
            let rect = CGRect(x: wide && index == 1 ? firstWidth + spacing : 0,
                              y: wide ? 0 : y, width: column, height: size.height)
            y = rect.maxY + spacing
            return rect
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: regions(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, region) in zip(subviews, regions(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + region.minX, y: bounds.minY + region.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(region.size))
        }
    }
}

struct NotebookInput<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content().padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Notebook.paper, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Notebook.rule) }
        }
    }
}

struct NumberedInstructions: View {
    let text: String
    var body: some View {
        let lines = text.split(whereSeparator: \.isNewline)
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(Notebook.fieldGreen)
                Text(String(line)).textSelection(.enabled)
            }
        }
    }
}

struct NotebookActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(prominent ? Color.white : Theme.burgundy)
            .background(prominent ? Theme.burgundy : Notebook.paper, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(prominent ? .clear : Notebook.rule) }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
