import SwiftUI
import Photos

struct ShareCardContent: Equatable {
    struct Section: Equatable { let heading: String; let body: String }
    var title: String
    var sections: [Section]
    var date: Date
    var author: String
    var isExample = false

    static func example(long: Bool = false) -> ShareCardContent {
        ShareCardContent(title: "场边训练安排 · 示例", sections: [
            Section(heading: "训练目标", body: "保持稳定节奏，专注每一次动作。此处为图片卡片示例，不是已保存的个人训练计划。"),
            Section(heading: "训练内容", body: long
                ? (1...45).map { "\($0). 热身后进行基础练习，每组保持动作质量；组间适当休息，观察身体感受并及时反馈。\n注意事项：按个人情况调整练习强度，完成后做放松整理。" }.joined(separator: "\n\n")
                : "热身与活动准备\n基础动作练习\n训练回顾与放松")
        ], date: Date(), author: "示例教练", isExample: true)
    }
}

/// TextKit flows the complete attributed content across fixed, readable pages.
/// No line limits or automatic font shrinking can silently omit long content.
@MainActor enum ShareCardRenderer {
    static let size = CGSize(width: 1080, height: 1440)
    enum Failure: LocalizedError {
        case tooLong, generation
        var errorDescription: String? {
            switch self { case .tooLong: return "内容超过单次 20 页图片范围，请拆分内容后生成。"; case .generation: return "图片未能生成，请重试。" }
        }
    }
    struct Page {
        let image: UIImage
        let summary: String
    }
    static func render(_ content: ShareCardContent) throws -> [UIImage] {
        try pages(content).map(\.image)
    }
    static func pages(_ content: ShareCardContent) throws -> [Page] {
        let text = NSMutableAttributedString(string: "")
        func append(_ string: String, font: UIFont, spacing: CGFloat, heading: Bool = false) {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 10; paragraph.paragraphSpacing = spacing
            paragraph.lineBreakMode = .byWordWrapping
            text.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: heading ? UIColor(Theme.burgundy) : UIColor(Notebook.ink), .paragraphStyle: paragraph]))
        }
        append(content.title, font: .systemFont(ofSize: 54, weight: .bold), spacing: 28)
        for section in content.sections {
            if !section.heading.isEmpty { append(section.heading, font: .systemFont(ofSize: 38, weight: .semibold), spacing: 12, heading: true) }
            append(section.body, font: .systemFont(ofSize: 36), spacing: 32)
        }
        append("署名：" + (content.author.isEmpty ? "未填写" : content.author), font: .systemFont(ofSize: 30), spacing: 0)
        guard text.length <= 100000 else { throw Failure.tooLong }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let bodySize = CGSize(width: 936, height: 1040)
        var containers: [NSTextContainer] = [], ranges: [NSRange] = []
        var end = 0
        repeat {
            guard containers.count < 20 else { throw Failure.tooLong }
            let container = NSTextContainer(size: bodySize); container.lineFragmentPadding = 0
            layout.addTextContainer(container); layout.ensureLayout(for: container)
            let range = layout.glyphRange(for: container)
            guard range.length > 0, NSMaxRange(range) > end else { throw Failure.generation }
            end = NSMaxRange(range); containers.append(container); ranges.append(range)
        } while end < layout.numberOfGlyphs
        var pages: [Page] = []
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        for index in containers.indices {
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(Notebook.paper).setFill(); context.fill(CGRect(origin: .zero, size: size))
                let burgundy = UIColor(red: 114/255, green: 47/255, blue: 55/255, alpha: 1)
                UIColor(Notebook.rule).setFill(); context.fill(CGRect(x: 72, y: 174, width: 936, height: 3)); context.fill(CGRect(x: 72, y: 1302, width: 936, height: 3))
                ("棒球训练助手 · Drill Buddy" as NSString).draw(at: CGPoint(x: 72, y: 58), withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: burgundy])
                let label = (content.isExample ? "示例内容 · " : "") + content.date.formatted(date: .numeric, time: .omitted)
                (label as NSString).draw(at: CGPoint(x: 72, y: 116), withAttributes: [.font: UIFont.systemFont(ofSize: 27), .foregroundColor: UIColor.darkGray])
                layout.drawBackground(forGlyphRange: ranges[index], at: CGPoint(x: 72, y: 220))
                layout.drawGlyphs(forGlyphRange: ranges[index], at: CGPoint(x: 72, y: 220))
                let navy = UIColor(red: 11/255, green: 25/255, blue: 51/255, alpha: 1)
                let brand = NSMutableAttributedString(string: "Baseball", attributes: [.font: UIFont(name: "Arial-BoldMT", size: 28)!, .kern: -1.26, .foregroundColor: navy])
                brand.append(NSAttributedString(string: "Master.cc", attributes: [.font: UIFont(name: "ArialMT", size: 28)!, .kern: -1.26, .foregroundColor: navy]))
                brand.draw(at: CGPoint(x: 72, y: 1330))
                ("\(index + 1) / \(containers.count)" as NSString).draw(at: CGPoint(x: 912, y: 1330), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .regular), .foregroundColor: UIColor.darkGray])
            }
            let range = layout.characterRange(forGlyphRange: ranges[index], actualGlyphRange: nil)
            let summary = (text.string as NSString).substring(with: range).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            pages.append(Page(image: image, summary: String(summary.prefix(50))))
        }
        return pages
    }
    static func files(for images: [UIImage], directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try images.enumerated().map { index, image in
                guard let data = image.pngData() else { throw Failure.generation }
                let url = directory.appendingPathComponent("训练卡片-\(index + 1).png")
                try data.write(to: url, options: .atomic); return url
            }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    static func saveToPhotos(_ images: [UIImage]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw BoardPhotos.Failure.permission }
        try await PHPhotoLibrary.shared().performChanges {
            for image in images { PHAssetChangeRequest.creationRequestForAsset(from: image) }
        }
    }
}

struct ShareCardPreview: View {
    let content: ShareCardContent
    @State private var pages: [ShareCardRenderer.Page] = []
    private var images: [UIImage] { pages.map(\.image) }
    @State private var page = 0
    @State private var wide = false
    @State private var issue: String?
    @State private var notice: String?
    @State private var saving = false
    @State private var share: CardExport?
    @State private var exportDirectory: URL?
    private struct CardExport: Identifiable { let id = UUID(); let urls: [URL] }
    var body: some View {
        ScrollView {
            NotebookColumns {
                VStack(alignment: .leading, spacing: 10) {
                    NotebookHeading(title: "图片预览", detail: content.title)
                    if images.indices.contains(page) {
                        Image(uiImage: images[page]).resizable().scaledToFit().frame(maxHeight: 600).padding(12).background(Notebook.inset, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("图片第 \(page + 1) 页，共 \(images.count) 页").accessibilityIdentifier("shareCardPage_\(page)")
                    }
                    HStack {
                        Button("上一页") { page -= 1 }.disabled(page == 0)
                        Spacer(); Text("\(images.isEmpty ? 0 : page + 1) / \(images.count)").monospacedDigit(); Spacer()
                        Button("下一页") { page += 1 }.disabled(page + 1 >= images.count)
                    }.buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("全部页面").font(.headline)
                    ForEach(images.indices, id: \.self) { i in
                        Button {
                            page = i
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: page == i ? "checkmark.circle.fill" : "doc")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("第 \(i + 1) 页").font(.subheadline.bold())
                                    Text(pages[i].summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(page == i ? Theme.burgundy.opacity(0.09) : Notebook.paper)
                                .overlay(alignment: .leading) { if page == i { Rectangle().fill(Theme.burgundy).frame(width: 3) } }
                        }.buttonStyle(.plain)
                    }
                    Button("重新生成") { generate() }.buttonStyle(.bordered).accessibilityIdentifier("shareCardRegenerate")
                    if wide { actions }
                }.notebookPanel()
            }.padding()
        }.background(Notebook.paper).notebookPageTitle("图片预览")
            .onGeometryChange(for: Bool.self) {
                $0.size.width >= 752
            } action: {
                wide = $0
            }
            .safeAreaInset(edge: .bottom) { if !wide { actions } }
            .onAppear { if images.isEmpty { generate() } }
            .onChange(of: content) { _, _ in generate() }
            .sheet(item: $share, onDismiss: cleanup) { export in
                CardActivitySheet(urls: export.urls) { completed, error in
                    notice = completed ? "分享已完成" : "已取消分享，图片仍可重新分享"
                    if let error { issue = error.localizedDescription }
                    share = nil
                }
        }
            .onDisappear { if share == nil { cleanup() } }
    }
    private var actions: some View {
            VStack(spacing: 8) {
                Text("共 \(images.count) 页").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("shareCardPageCount")
                if let issue { Text(issue).font(.callout).foregroundStyle(.red).accessibilityIdentifier("shareCardIssue") }
                if let notice { Text(notice).font(.callout).foregroundStyle(Theme.burgundy).accessibilityIdentifier("shareCardNotice") }
            let layout = wide ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button("系统分享", systemImage: "square.and.arrow.up") { shareImages() }.buttonStyle(NotebookActionStyle(prominent: true)).accessibilityIdentifier("shareCardShare")
                Button(saving ? "正在保存…" : "保存全部图片") {
                    saving = true; notice = nil; issue = nil
                    let snapshot = images
                    Task {
                        defer { saving = false }
                        do { try await ShareCardRenderer.saveToPhotos(snapshot); notice = "已保存 \(snapshot.count) 张图片到相册" }
                        catch { issue = error.localizedDescription }
                    }
                }.buttonStyle(NotebookActionStyle()).accessibilityIdentifier("shareCardSave")
            }
                .disabled(images.isEmpty || saving)
            }.padding(12).frame(maxWidth: .infinity).background(Theme.paper)
        }
    private func generate() {
        issue = nil; notice = nil; pages = []; page = 0
        do { pages = try ShareCardRenderer.pages(content) }
        catch { issue = error.localizedDescription }
    }
    private func shareImages() {
        cleanup(); issue = nil
        let directory = URL.temporaryDirectory.appendingPathComponent("ShareCards").appendingPathComponent(UUID().uuidString)
        do {
            let urls = try ShareCardRenderer.files(for: images, directory: directory)
            exportDirectory = directory; share = CardExport(urls: urls)
        } catch { issue = error.localizedDescription }
    }
    private func cleanup() {
        if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
        exportDirectory = nil
    }
}

private struct CardActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    let completion: (Bool, Error?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#if DEBUG
struct ShareCardExampleView: View {
    @State private var long = false
    // Stable date avoids regenerating on an unrelated state redraw.
    @State private var date = Date()
    var body: some View {
        VStack(spacing: 0) {
            Toggle("长内容分页示例", isOn: $long).padding().accessibilityIdentifier("shareCardLongExample")
            ShareCardPreview(content: content)
        }
    }
    private var content: ShareCardContent {
        var value = ShareCardContent.example(long: long); value.date = date; return value
    }
}
#endif
