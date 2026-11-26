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
            .background(Notebook.paper)
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

/// Presentation shared by the four saved coaching document types.
struct NotebookDocument: Identifiable {
    let id: UUID
    let title: String
    let audience: String
    let date: Date
    let lead: String
    let footer: String
    let rowDetail: String
}

struct DocumentLibrary<Detail: View>: View {
    let title: String
    let noun: String
    let icon: String
    let documents: [NotebookDocument]
    let issue: String?
    let createID: String
    let retry: () -> Void
    let create: () -> Void
    @ViewBuilder let detail: (UUID, Bool) -> Detail
    @State private var selection: UUID?
    @ScaledMetric(relativeTo: .title2) private var headingSize = 25.0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 660 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title).font(.system(size: wide ? headingSize * 34 / 25 : headingSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                            Text("本机保存 · \(documents.count) 份" + noun).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: create) { Label("新建", systemImage: "plus") }
                            .buttonStyle(DocumentButtonStyle(primary: true)).disabled(issue != nil)
                            .accessibilityIdentifier(createID)
                    }.padding(.bottom, 19)
                    Rectangle().fill(Notebook.rule).frame(height: 1)
                    if let issue { Text(issue).foregroundStyle(.red); Button("重试读取", action: retry) }
                    if let first = documents.first {
                        if wide {
                            let selected = documents.first(where: { $0.id == selection }) ?? first
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 0) {
                                    section("已保存", count: documents.count)
                                    ForEach(documents) { doc in
                                        Button { selection = doc.id } label: { row(doc, selected: doc.id == selected.id) }.buttonStyle(.plain)
                                    }
                                }.frame(width: max(182, (min(1060, geo.size.width) - 88) * 0.355))
                                VStack(alignment: .leading, spacing: 0) {
                                    section("所选" + noun)
                                    detail(selected.id, true).id(selected.id)
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            section("最近保存")
                            NavigationLink { detail(first.id, false) } label: {
                                LatestTrainingCard(title: first.title, audience: first.audience.isEmpty ? title : first.audience,
                                                   date: first.date, summary: first.lead, action: first.footer, icon: icon)
                            }.buttonStyle(.plain)
                            if documents.count > 1 {
                                section("其他" + noun, count: documents.count - 1)
                                line
                                ForEach(documents.dropFirst()) { doc in
                                    NavigationLink { detail(doc.id, false) } label: { row(doc, selected: false) }.buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("还没有" + title, systemImage: icon, description: Text("点「新建」开始填写。"))
                    }
                }.padding(.horizontal, wide ? 32 : 15).padding(.top, wide ? 24 : 17).padding(.bottom, 26)
                    .frame(maxWidth: 1060).frame(maxWidth: .infinity)
            }.background(Notebook.paper)
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private var line: some View { Rectangle().fill(Notebook.rule).frame(height: 1) }
    private func section(_ name: String, count: Int? = nil) -> some View {
        HStack {
            Text(name).font(.headline).accessibilityAddTraits(.isHeader); Spacer()
            if let count { Text("\(count) 份").font(.subheadline).foregroundStyle(.secondary) }
        }.padding(.top, 20).padding(.bottom, 9)
    }
    private func row(_ doc: NotebookDocument, selected: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(String(Calendar.current.component(.day, from: doc.date))).font(.system(.title2, design: .monospaced).bold())
                    Text("\(Calendar.current.component(.month, from: doc.date))月").font(.caption)
                }.frame(width: 40).overlay(alignment: .trailing) { Rectangle().fill(Notebook.rule).frame(width: 1) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.title).font(.headline).foregroundStyle(selected ? Theme.burgundy : Notebook.ink)
                    Text(doc.rowDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "arrow.right").font(.caption)
            }.padding(.horizontal, selected ? 9 : 2).frame(minHeight: 74)
            line
        }.contentShape(Rectangle()).background(selected ? Theme.burgundy.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.burgundy).frame(width: 3) } }
    }
}

struct DocumentButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.readerActionsExpanded) private var expanded
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(maxWidth: expanded && primary ? .infinity : nil)
            .padding(.horizontal, 13).padding(.vertical, 5).frame(minHeight: 44)
            .foregroundStyle(primary ? Color.white : Notebook.ink)
            .background(primary ? Theme.burgundy : Notebook.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : Notebook.rule) }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.48)
    }
}

struct LatestTrainingCard: View {
    let title: String
    let audience: String
    let date: Date
    let summary: String
    let action: String
    let icon: String
    @ScaledMetric(relativeTo: .title2) private var titleSize = 25.0
    @ScaledMetric(relativeTo: .footnote) private var copySize = 13.0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(audience, systemImage: icon); Spacer()
                Text(date.formatted(.verbatim("\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits)", timeZone: .current, calendar: .current)))
                    .font(.system(.caption, design: .monospaced))
            }.font(.system(size: copySize, weight: .medium)).foregroundStyle(.secondary)
            Text(title).font(.system(size: titleSize, weight: .bold)).padding(.top, 15)
            if !summary.isEmpty { Text(summary).font(.system(size: copySize)).lineSpacing(4).lineLimit(2).padding(.top, 5) }
            Divider().padding(.top, 16)
            HStack { Text(action); Spacer(); Image(systemName: "arrow.right") }
                .font(.system(size: copySize, weight: .semibold)).foregroundStyle(Theme.burgundy).padding(.top, 10)
        }.padding(.horizontal, 18).padding(.top, 17).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 247/255, green: 246/255, blue: 240/255), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 198/255, green: 195/255, blue: 183/255)) }
            .contentShape(Rectangle())
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

struct DocumentActions<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary
    @Environment(\.readerSidebar) private var sidebar
    var body: some View {
        if sidebar {
            VStack(alignment: .leading, spacing: 8) {
                primary().environment(\.readerActionsExpanded, true)
                HStack(spacing: 8) { secondary() }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { primary(); secondary() }
                VStack(alignment: .leading, spacing: 8) { primary(); secondary() }
            }
        }
    }
}

struct DocumentReader<Paper: View, Actions: View>: View {
    var sections: [String] = []
    @ViewBuilder var paper: () -> Paper
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            ScrollViewReader { scroll in
                if wide {
                    ScrollView {
                        NotebookColumns(minimumWidth: 0, leadingFraction: 0.64) {
                            paper().overlay(alignment: .top) { Rectangle().fill(Theme.burgundy).frame(height: 2) }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("本页动作").font(.headline)
                                actions().environment(\.readerSidebar, true)
                                if !sections.isEmpty {
                                    Divider()
                                    Text("内容目录").font(.headline)
                                    ForEach(sections, id: \.self) { section in
                                        Button { withAnimation { scroll.scrollTo(section, anchor: .top) } } label: {
                                            HStack { Text(section); Spacer(); Image(systemName: "arrow.down") }
                                                .frame(minHeight: 44).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            }
                        }.padding(24)
                    }
                } else {
                    ViewThatFits(in: .vertical) {
                        VStack(alignment: .leading, spacing: 0) { paper().padding(15); footer }
                            .fixedSize(horizontal: false, vertical: true)
                        ScrollView { paper().padding(15) }
                            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            actions().environment(\.readerActionsExpanded, true).padding(.horizontal, 12)
        }.padding(.bottom, 6).frame(maxWidth: .infinity).background(Notebook.paper)
    }

}

struct DocumentEditorLayout<Form: View, Preview: View>: View {
    let title: String
    let context: String
    let navigationTitle: String
    let canSave: Bool
    let saveID: String
    let cancelID: String
    let cancel: () -> Void
    let save: () -> Void
    @Binding var showingPreview: Bool
    @ViewBuilder var form: () -> Form
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Text(navigationTitle).font(.headline)
                    HStack {
                        Button(action: cancel) { Label("取消", systemImage: "chevron.left") }
                            .accessibilityIdentifier(cancelID)
                        Spacer()
                    }.padding(.horizontal, 15)
                }.frame(minHeight: 44)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.bold())
                        Text(context).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !wide || showingPreview {
                        Button { showingPreview.toggle() } label: {
                            Image(systemName: showingPreview ? "pencil" : "eye")
                                .accessibilityLabel(showingPreview ? "填写" : "预览")
                        }.buttonStyle(DocumentButtonStyle()).accessibilityIdentifier("documentPreviewToggle")
                    }
                    Button(action: save) { Label("保存", systemImage: "checkmark") }
                        .buttonStyle(DocumentButtonStyle(primary: true)).disabled(!canSave).accessibilityIdentifier(saveID)
                }.padding(.horizontal, wide ? 24 : 15).padding(.vertical, 12)
                Divider()
                if showingPreview { preview() } else if wide {
                    HStack(alignment: .top, spacing: 0) {
                        form().frame(width: geometry.size.width * 0.49)
                        Divider()
                        preview().frame(maxWidth: .infinity)
                    }
                } else { form() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background(Notebook.paper).foregroundStyle(Notebook.ink).tint(Theme.burgundy)
            .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ReaderSidebarKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var readerSidebar: Bool {
        get { self[ReaderSidebarKey.self] }
        set { self[ReaderSidebarKey.self] = newValue }
    }
}

private struct ReaderActionsExpandedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var readerActionsExpanded: Bool {
        get { self[ReaderActionsExpandedKey.self] }
        set { self[ReaderActionsExpandedKey.self] = newValue }
    }
}

private struct NotebookDirectoryKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openNotebookDirectory: (() -> Void)? {
        get { self[NotebookDirectoryKey.self] }
        set { self[NotebookDirectoryKey.self] = newValue }
    }
}

/// Keep child pages inside the navigation column so the iPad scene rail remains interactive.
extension View {
    func notebookDestination<Item, Page: View>(item: Binding<Item?>, @ViewBuilder page: @escaping (Item) -> Page) -> some View {
        navigationDestination(isPresented: Binding(get: { item.wrappedValue != nil }, set: { active in
            if !active { item.wrappedValue = nil }
        })) {
            if let selected = item.wrappedValue { page(selected).navigationBarBackButtonHidden() }
        }
    }

    func notebookPageTitle(_ title: String, parent: String = "返回", backID: String = "notebookBack", back: (() -> Void)? = nil) -> some View {
        modifier(NotebookDetailHeader(title: title, parent: parent, backID: backID, back: back))
    }
}

struct NotebookPageBar<Actions: View>: View {
    let title: String
    let parent: String
    let backID: String
    let back: () -> Void
    @ViewBuilder var actions: () -> Actions
    @Environment(\.openNotebookDirectory) private var directory
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.headline)
                HStack(spacing: 0) {
                    Button(action: back) { Label(parent, systemImage: "chevron.left").frame(minHeight: 44) }
                        .accessibilityIdentifier(backID)
                    Spacer()
                    actions()
                    if let directory {
                        Button(action: directory) { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }.accessibilityLabel("页面目录")
                    }
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.burgundy).padding(.leading, 15)
            }.frame(minHeight: 44)
            Divider()
        }.background(Notebook.paper).foregroundStyle(Notebook.ink)
    }
}

private struct NotebookDetailHeader: ViewModifier {
    let title: String
    let parent: String
    let backID: String
    let back: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            NotebookPageBar(title: title, parent: parent, backID: backID, back: back ?? { dismiss() }) { EmptyView() }
        }.toolbar(.hidden, for: .navigationBar)
    }
}
