import UIKit

extension UnitPointValue {
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
extension ViewSettings {
    func geometry(image: CGSize, viewport: CGSize) -> VideoGeometry {
        VideoGeometry(imageSize: image, viewportSize: viewport,
                      crop: CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3]),
                      quarterTurns: quarterTurns, mirrored: mirrored, zoom: zoom,
                      pan: CGPoint(x: pan.x * viewport.width, y: pan.y * viewport.height))
    }
}
extension UIColor {
    convenience init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x722F37
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

enum AnalysisRenderer {
    static func visible(_ annotation: Annotation, at time: Double, tolerance: Double) -> Bool {
        time >= annotation.range.start.seconds - tolerance && time < annotation.range.end.seconds
    }
    static func render(image: CGImage, size: CGSize, settings: ViewSettings, annotations: [Annotation],
                       pose: PoseFrame? = nil, confidence: Float = 0.3, showAngles: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            draw(image: image, in: output.cgContext, size: size, settings: settings,
                 annotations: annotations, pose: pose, confidence: confidence, showAngles: showAngles)
        }
    }
    static func draw(image: CGImage, in context: CGContext, size: CGSize, settings: ViewSettings,
                     annotations: [Annotation], pose: PoseFrame?, confidence: Float, showAngles: Bool = true) {
        context.saveGState(); defer { context.restoreGState() }
        context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(origin: .zero, size: size))
        let geometry = settings.geometry(image: CGSize(width: image.width, height: image.height), viewport: size)
        guard geometry.isValid else { return }
        let origin = geometry.viewPoint(from: .zero), x = geometry.viewPoint(from: CGPoint(x: 1, y: 0)), y = geometry.viewPoint(from: CGPoint(x: 0, y: 1))
        context.saveGState()
        context.concatenate(CGAffineTransform(a: (x.x - origin.x) / CGFloat(image.width),
                                             b: (x.y - origin.y) / CGFloat(image.width),
                                             c: (y.x - origin.x) / CGFloat(image.height),
                                             d: (y.y - origin.y) / CGFloat(image.height), tx: origin.x, ty: origin.y))
        let crop = geometry.crop
        context.clip(to: CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
                                width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height)))
        // UIKit draws CGImage in upright, top-left image coordinates.
        UIGraphicsPushContext(context)
        UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        UIGraphicsPopContext(); context.restoreGState()
        let cropPoints = [CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.minY),
                          CGPoint(x: crop.maxX, y: crop.maxY), CGPoint(x: crop.minX, y: crop.maxY)].map { geometry.viewPoint(from: $0) }
        context.beginPath(); context.addLines(between: cropPoints); context.closePath(); context.clip()
        for annotation in annotations { draw(annotation, context: context, geometry: geometry) }
        if let pose { drawPose(pose, context: context, geometry: geometry, confidence: confidence, showAngles: showAngles) }
    }
    static func draw(_ annotation: Annotation, context: CGContext, geometry: VideoGeometry) {
        let points = annotation.points.map { geometry.viewPoint(from: $0.cgPoint) }
        guard let first = points.first else { return }
        context.saveGState(); defer { context.restoreGState() }
        let color = UIColor(hex: annotation.color)
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(annotation.lineWidth * min(geometry.viewportSize.width, geometry.viewportSize.height) / 360)
        context.setLineCap(.round); context.setLineJoin(.round)
        if annotation.kind == "text" {
            text(annotation.text ?? "", at: first, color: color, size: max(14, 18 * geometry.viewportSize.width / 600)); return
        }
        if annotation.kind == "ellipse", points.count >= 2 {
            // Construct the ellipse in source coordinates, then transform each sample.
            let a = annotation.points[0].cgPoint, b = annotation.points[1].cgPoint
            var outline: [CGPoint] = []
            let centerX = (a.x + b.x) / 2, centerY = (a.y + b.y) / 2
            let radiusX = abs(a.x - b.x) / 2, radiusY = abs(a.y - b.y) / 2
            for i in 0...64 {
                let angle = CGFloat(i) / 64 * 2 * CGFloat.pi
                let point = CGPoint(x: centerX + radiusX * cos(angle), y: centerY + radiusY * sin(angle))
                outline.append(geometry.viewPoint(from: point))
            }
            context.addLines(between: outline); context.strokePath(); return
        }
        context.addLines(between: points); context.strokePath()
        if annotation.kind == "arrow", points.count >= 2, let end = points.last {
            let before = points[points.count - 2], angle = atan2(end.y - before.y, end.x - before.x)
            let length = max(10, annotation.lineWidth * 4) * geometry.viewportSize.width / 600
            context.addLines(between: [CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)), end,
                                      CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))]); context.strokePath()
        }
        if annotation.kind == "angle", annotation.points.count == 3,
           let angle = VideoGeometry.angle(a: annotation.points[0].cgPoint, vertex: annotation.points[1].cgPoint,
                                          b: annotation.points[2].cgPoint, imageSize: geometry.imageSize) {
            text(String(format: "%.1f°", angle), at: points[1], color: color, size: 16)
        }
    }
    static let bones = [("leftShoulder","rightShoulder"),("leftShoulder","leftElbow"),("leftElbow","leftWrist"),
                        ("rightShoulder","rightElbow"),("rightElbow","rightWrist"),("leftShoulder","leftHip"),
                        ("rightShoulder","rightHip"),("leftHip","rightHip"),("leftHip","leftKnee"),("leftKnee","leftAnkle"),
                        ("rightHip","rightKnee"),("rightKnee","rightAnkle")]
    static func drawPose(_ pose: PoseFrame, context: CGContext, geometry: VideoGeometry, confidence: Float, showAngles: Bool) {
        let joints = Dictionary(pose.joints.filter { $0.confidence >= confidence }.map { ($0.name, $0.position.cgPoint) }, uniquingKeysWith: { a, _ in a })
        context.setStrokeColor(UIColor.systemCyan.cgColor); context.setFillColor(UIColor.systemCyan.cgColor); context.setLineWidth(2.5)
        for (a, b) in bones {
            if let a = joints[a], let b = joints[b] { context.addLines(between: [geometry.viewPoint(from: a), geometry.viewPoint(from: b)]); context.strokePath() }
        }
        for (_, point) in joints {
            let view = geometry.viewPoint(from: point); context.fillEllipse(in: CGRect(x: view.x - 3, y: view.y - 3, width: 6, height: 6))
        }
        if showAngles {
            for angle in PoseMetrics.angles(joints: joints, size: geometry.imageSize, quarterTurns:geometry.quarterTurns) {
                text("\(angle.name) \(Int(angle.degrees.rounded()))°", at: geometry.viewPoint(from: angle.point), color: .cyan, size: 13)
            }
        }
    }
    static func text(_ text: String, at point: CGPoint, color: UIColor, size: CGFloat) {
        (text as NSString).draw(at: CGPoint(x: point.x + 4, y: point.y + 4), withAttributes: [
            .foregroundColor: color, .font: UIFont.boldSystemFont(ofSize: size),
            .strokeColor: UIColor.black, .strokeWidth: -2])
    }
}

enum PoseMetrics {
    struct Angle { let name: String; let degrees: Double; let point: CGPoint }
    static func angles(joints: [String: CGPoint], size: CGSize, quarterTurns:Int=0) -> [Angle] {
        var result: [Angle] = []
        for side in ["left", "right"] {
            for (label, a, vertex, b) in [("肘", "Shoulder", "Elbow", "Wrist"), ("膝", "Hip", "Knee", "Ankle")] {
                if let a = joints[side+a], let v = joints[side+vertex], let b = joints[side+b],
                   let value = VideoGeometry.angle(a: a, vertex: v, b: b, imageSize: size) {
                    result.append(Angle(name: (side == "left" ? "左" : "右") + label, degrees: value, point: v))
                }
            }
        }
        if let ls = joints["leftShoulder"], let rs = joints["rightShoulder"], let lh = joints["leftHip"], let rh = joints["rightHip"] {
            let shoulder = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let hip = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
            let dx = (shoulder.x - hip.x) * size.width, dy = (shoulder.y - hip.y) * size.height
            if hypot(dx, dy) > 0.001 { result.append(Angle(name: "躯干", degrees: Double(atan2(quarterTurns % 2 == 0 ? abs(dx):abs(dy), quarterTurns % 2 == 0 ? abs(dy):abs(dx))) * 180 / Double.pi, point: hip)) }
        }
        return result
    }
}
