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
