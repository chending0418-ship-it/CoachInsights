import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct ImportedPhoto { let url: URL; let timing: MediaMetadata?; let notice: String? }

struct PhotoImportView:View {
    let completion:(Result<ImportedPhoto,Error>)->Void
    @State private var loading=false
    var body:some View {
        ZStack {
            PhotoImportPicker(completion:completion,onLoading:{loading=true})
            if loading {
                VStack(spacing:16) {
                    ProgressView("正在读取所选视频…")
                    Text("随后复制到本机资料库。").font(.caption).foregroundStyle(.secondary)
                    Button("取消导入",role:.cancel) { completion(.failure(CancellationError())) }
                }.padding(28).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
            }
        }
    }
}

private struct PhotoImportPicker: UIViewControllerRepresentable {
    let completion: (Result<ImportedPhoto, Error>) -> Void
    let onLoading:()->Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion,onLoading:onLoading) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos; configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: PHPickerViewController, coordinator: Coordinator) { coordinator.task?.cancel() }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<ImportedPhoto, Error>) -> Void
        var task: Task<Void,Never>?
        let onLoading:()->Void
        init(completion: @escaping (Result<ImportedPhoto, Error>) -> Void,onLoading:@escaping ()->Void) { self.completion = completion;self.onLoading=onLoading }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else { completion(.failure(CancellationError())); return }
            onLoading()
            // Keep the picker visible while the selected provider makes its local copy.
            task = Task { @MainActor in
                do {
                    if let id = result.assetIdentifier {
                        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        if authorization == .authorized || authorization == .limited,
                           let photo = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                            let selection = try await PhotoVideoSource().load(photo)
                            if let source = selection.sourceAsset as? AVURLAsset {
                                let timing = try await MediaInspector().inspect(asset: selection.analysisAsset)
                                try Task.checkCancellation()
                                completion(.success(ImportedPhoto(url: source.url, timing: timing, notice: selection.notice))); return
                            }
                        }
                    }
                    // Providers without PHAsset access deliver an independent, selected movie only.
                    let url = try await Self.copyProvider(result.itemProvider)
                    try Task.checkCancellation()
                    completion(.success(ImportedPhoto(url: url, timing: nil,
                        notice: "已导入所选视频的本机副本。相册编辑版按其交付帧时间分析。")))
                } catch { completion(.failure(Task.isCancelled ? CancellationError():error)) }
            }
        }
        static func copyProvider(_ provider: NSItemProvider) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    do {
                        guard let url else { throw error ?? MediaFailure.readFailed }
                        let local = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                        try FileManager.default.copyItem(at: url, to: local)
                        continuation.resume(returning: local)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
