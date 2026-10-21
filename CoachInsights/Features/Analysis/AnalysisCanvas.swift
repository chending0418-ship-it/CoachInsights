import SwiftUI
import AVFoundation

struct AnalysisCanvas: UIViewRepresentable {
    @ObservedObject var workspace: AnalysisWorkspace
    func makeUIView(context: Context) -> AnalysisCanvasView { AnalysisCanvasView() }
    func updateUIView(_ view: AnalysisCanvasView, context: Context) {
        view.frameKey = (workspace.selectedVideoID?.uuidString ?? "") + ":" + String(workspace.frameIndex)
        view.image = workspace.frame?.image
        view.playerLayer.player = workspace.playback?.player
        view.live = workspace.playing || workspace.frame?.index != workspace.frameIndex
        view.isUserInteractionEnabled = workspace.tool == "view" || (!workspace.playing && workspace.frame?.index == workspace.frameIndex)
        view.settings = workspace.viewSettings
        view.annotations = workspace.visibleAnnotations
        view.pose = workspace.currentPose
        view.confidence = workspace.poseSettings.minimumConfidence
        view.tool = workspace.tool
        view.selectedID = workspace.selectedAnnotation
        view.strokeColor = workspace.color
        view.strokeWidth = workspace.lineWidth
        view.textValue = workspace.textValue
        view.imageSize = workspace.metadata?.displaySize ?? CGSize(width: 16, height: 9)
        view.onAdd = { workspace.add(points: $0) }
        view.onEdit = { workspace.replace($0) }
        view.onSelect = { workspace.selectedAnnotation = $0 }
        view.onView = { workspace.updateView($0) }
        view.setNeedsLayout(); view.setNeedsDisplay()
    }
    static func dismantleUIView(_ uiView: AnalysisCanvasView, coordinator: ()) { uiView.playerLayer.player = nil }
}

final class AnalysisCanvasView: UIView, UIGestureRecognizerDelegate {
    var frameKey="" { didSet { if frameKey != oldValue { draft=[];start=nil;original=nil;edit=nil } } }
    var image: CGImage?
    let playerLayer = AVPlayerLayer()
    var live = false
    var imageSize = CGSize(width: 16, height: 9)
    var settings = ViewSettings()
    var annotations: [Annotation] = []
    var pose: PoseFrame?
    var confidence: Float = 0.3
    var tool = "view" { didSet { if oldValue != tool { draft.removeAll(); setNeedsDisplay() } } }
    var selectedID: UUID?
    var strokeColor = "#722F37"
    var strokeWidth: Double = 3
    var textValue = "关注点"
    var onAdd: (([UnitPointValue]) -> Void)?
    var onEdit: ((Annotation) -> Void)?
    var onSelect: ((UUID?) -> Void)?
    var onView: ((ViewSettings) -> Void)?
    private var draft: [UnitPointValue] = []
    private var start: CGPoint?
    private var original: Annotation?
    private var originalSettings: ViewSettings?
    private var handleIndex: Int?
    private var edit: Annotation?
    private var pinchStart: Double = 1
    private var geometry: VideoGeometry { settings.geometry(image: imageSize, viewport: bounds.size) }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true; backgroundColor = .black; clipsToBounds = true; isMultipleTouchEnabled = true
        layer.addSublayer(playerLayer)
        let touch = CanvasTouchRecognizer(target: nil, action: nil)
        touch.cancelsTouchesInView = false; touch.delaysTouchesBegan = false; touch.delaysTouchesEnded = false; touch.delegate = self
        addGestureRecognizer(touch)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self; addGestureRecognizer(pinch)
        accessibilityIdentifier = "analysisCanvas"
        accessibilityLabel = "视频分析画布"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.isHidden = !live
        guard geometry.isValid else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.bounds = CGRect(origin: .zero, size: imageSize)
        let a = geometry.viewPoint(from: .zero), b = geometry.viewPoint(from: CGPoint(x: 1, y: 0)), c = geometry.viewPoint(from: CGPoint(x: 0, y: 1))
        playerLayer.setAffineTransform(CGAffineTransform(a: (b.x-a.x)/imageSize.width, b: (b.y-a.y)/imageSize.width,
                                                       c: (c.x-a.x)/imageSize.height, d: (c.y-a.y)/imageSize.height, tx: 0, ty: 0))
        playerLayer.position = geometry.viewPoint(from: CGPoint(x: 0.5, y: 0.5))
        let mask = CAShapeLayer()
        let crop = geometry.crop
        mask.path = CGPath(rect: CGRect(x: crop.minX * imageSize.width, y: crop.minY * imageSize.height, width: crop.width * imageSize.width, height: crop.height * imageSize.height), transform: nil)
        playerLayer.mask = mask
        playerLayer.videoGravity = .resize
        CATransaction.commit()
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), geometry.isValid else { return }
        if !live, let image {
            AnalysisRenderer.draw(image: image, in: context, size: bounds.size, settings: settings,
                                  annotations: [], pose: nil, confidence: confidence)
        } else { context.setFillColor(UIColor.black.cgColor); context.fill(bounds) }
        // Live player sits above this view's backing store; a transparent overlay layer draws its marks.
        overlay.image = image; overlay.geometry = geometry; overlay.annotations = annotations.filter { $0.id != edit?.id } + (edit.map { [$0] } ?? [])
        overlay.pose = pose; overlay.confidence = confidence; overlay.selectedID = selectedID
        overlay.draft = draft; overlay.tool = tool; overlay.strokeColor = strokeColor; overlay.strokeWidth = strokeWidth
        if overlay.superview == nil { addSubview(overlay); overlay.isUserInteractionEnabled = false }
        overlay.frame = bounds; overlay.setNeedsDisplay()
    }
    private let overlay = CanvasOverlay()
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard tool == "view" else { return }
        if gesture.state == .began { pinchStart = settings.zoom }
        var value = settings; value.zoom = min(8, max(1, pinchStart * Double(gesture.scale)))
        settings = value; setNeedsDisplay(); setNeedsLayout()
        if gesture.state == .ended { onView?(value) }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, geometry.isValid else { return }
        let location = touch.location(in: self)
        start = location; originalSettings = settings
        if tool == "select" {
            if let selected = annotations.first(where: { $0.id == selectedID }),
               let index = selected.points.indices.min(by: {
                   distance(geometry.viewPoint(from: selected.points[$0].cgPoint), location) < distance(geometry.viewPoint(from: selected.points[$1].cgPoint), location)
               }), distance(geometry.viewPoint(from: selected.points[index].cgPoint), location) < 24 {
                original = selected; edit = selected; handleIndex = index
            } else {
                let hit = annotations.reversed().first { annotation in
                    let points = annotation.points.map { geometry.viewPoint(from: $0.cgPoint) }
                    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                          let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return false }
                    return CGRect(x: minX, y: minY, width: max(1, maxX-minX), height: max(1, maxY-minY)).insetBy(dx: -18, dy: -18).contains(location)
                }
                onSelect?(hit?.id); selectedID = hit?.id; original = hit; edit = hit; handleIndex = nil
            }
        } else if tool != "view", let point = geometry.normalizedPoint(from: location) {
            if tool == "angle" { draft.append(UnitPointValue(point)) }
            else { draft = [UnitPointValue(point)] }
        }
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self), let start else { return }
        if tool == "view", let originalSettings {
            settings.pan.x = originalSettings.pan.x + (location.x-start.x)/bounds.width
            settings.pan.y = originalSettings.pan.y + (location.y-start.y)/bounds.height
            setNeedsLayout()
        } else if tool == "select", let original,
                  let a = geometry.normalizedPoint(from: start, allowOutside: true),
                  let b = geometry.normalizedPoint(from: location, allowOutside: true) {
            var value = original
            if let handleIndex { value.points[handleIndex] = UnitPointValue(clamp(b)) }
            else { value.points = original.points.map { UnitPointValue(clamp(CGPoint(x: $0.x+b.x-a.x, y: $0.y+b.y-a.y))) } }
            edit = value
        } else if tool != "angle", tool != "text", let point = geometry.normalizedPoint(from: location, allowOutside: true), !draft.isEmpty {
            if tool == "freehand" { draft.append(UnitPointValue(clamp(point))) }
            else { draft = [draft[0], UnitPointValue(clamp(point))] }
        }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if tool == "view" { onView?(settings) }
        else if tool == "select", let edit { onEdit?(edit) }
        else if tool == "angle" {
            if draft.count == 3 { onAdd?(draft); draft.removeAll() }
        } else if tool == "text" || draft.count >= 2 { onAdd?(draft); draft.removeAll() }
        start = nil; original = nil; edit = nil; setNeedsDisplay()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        start = nil; original = nil; edit = nil; draft.removeAll(); setNeedsDisplay()
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
    private func clamp(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1,max(0,p.x)), y: min(1,max(0,p.y))) }
}

private final class CanvasOverlay: UIView {
    var image: CGImage?
    var geometry = VideoGeometry(imageSize: .zero, viewportSize: .zero)
    var annotations: [Annotation] = []; var pose: PoseFrame?; var confidence: Float = 0.3
    var selectedID: UUID?; var draft: [UnitPointValue] = []; var tool = "line"; var strokeColor = "#722F37"; var strokeWidth: Double = 3
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), geometry.isValid else { return }
        let crop = geometry.crop
        let corners = [CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.maxY), CGPoint(x: crop.minX, y: crop.maxY)].map { geometry.viewPoint(from: $0) }
        context.saveGState()
        context.addLines(between: corners); context.closePath(); context.clip()
        for annotation in annotations { AnalysisRenderer.draw(annotation, context: context, geometry: geometry) }
        if !draft.isEmpty {
            AnalysisRenderer.draw(Annotation(videoID: UUID(), kind: tool, points: draft, color: strokeColor, lineWidth: strokeWidth,
                                             range: ClipRange(start: MediaTime(seconds: 0), end: MediaTime(seconds: 1))), context: context, geometry: geometry)
        }
        if let pose { AnalysisRenderer.drawPose(pose, context: context, geometry: geometry, confidence: confidence, showAngles: true) }
        if let selected = annotations.first(where: { $0.id == selectedID }) {
            for point in selected.points {
                let p = geometry.viewPoint(from: point.cgPoint)
                context.setFillColor(UIColor.white.cgColor); context.fillEllipse(in: CGRect(x:p.x-5,y:p.y-5,width:10,height:10))
                context.setStrokeColor(UIColor(hex: "#722F37").cgColor); context.strokeEllipse(in: CGRect(x:p.x-5,y:p.y-5,width:10,height:10))
            }
        }
        context.restoreGState()
        AnalysisRenderer.drawPoseNotice(pose, context: context, size: bounds.size, confidence: confidence)
    }
}

// Claim canvas touches immediately so the surrounding page cannot steal a drawing stroke.
private final class CanvasTouchRecognizer:UIGestureRecognizer {
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) { state = .began }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) { state = .changed }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) { state = .ended }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) { state = .cancelled }
}
