import CoreGraphics
import Foundation

struct VideoGeometry {
    let imageSize: CGSize
    let viewportSize: CGSize
    var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var quarterTurns = 0
    var mirrored = false
    var zoom: CGFloat = 1
    var pan: CGPoint = .zero

    private var turn: Int { ((quarterTurns % 4) + 4) % 4 }
    private var sourceSize: CGSize {
        CGSize(width: imageSize.width * crop.width, height: imageSize.height * crop.height)
    }
    var rotatedSize: CGSize {
        turn % 2 == 0 ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)
    }
    var scale: CGFloat {
        guard rotatedSize.width > 0, rotatedSize.height > 0 else { return 0 }
        return min(viewportSize.width / rotatedSize.width, viewportSize.height / rotatedSize.height) * zoom
    }
    var isValid: Bool {
        imageSize.width > 0 && imageSize.height > 0 && viewportSize.width > 0
            && viewportSize.height > 0 && crop.width > 0 && crop.height > 0
            && crop.minX >= 0 && crop.minY >= 0 && crop.maxX <= 1 && crop.maxY <= 1 && zoom > 0
    }

    func viewPoint(from normalized: CGPoint) -> CGPoint {
        precondition(isValid)
        var x = (normalized.x - crop.minX) * imageSize.width
        var y = (normalized.y - crop.minY) * imageSize.height
        let w = sourceSize.width, h = sourceSize.height
        if mirrored { x = w - x }
        switch turn {
        case 1: (x, y) = (h - y, x)
        case 2: (x, y) = (w - x, h - y)
        case 3: (x, y) = (y, w - x)
        default: break
        }
        return CGPoint(x: viewportSize.width / 2 + pan.x + (x - rotatedSize.width / 2) * scale,
                       y: viewportSize.height / 2 + pan.y + (y - rotatedSize.height / 2) * scale)
    }

    func normalizedPoint(from view: CGPoint, allowOutside: Bool = false) -> CGPoint? {
        guard isValid else { return nil }
        var x = (view.x - viewportSize.width / 2 - pan.x) / scale + rotatedSize.width / 2
        var y = (view.y - viewportSize.height / 2 - pan.y) / scale + rotatedSize.height / 2
        let w = sourceSize.width, h = sourceSize.height
        switch turn {
        case 1: (x, y) = (y, h - x)
        case 2: (x, y) = (w - x, h - y)
        case 3: (x, y) = (w - y, x)
        default: break
        }
        if mirrored { x = w - x }
        let result = CGPoint(x: x / imageSize.width + crop.minX,
                             y: y / imageSize.height + crop.minY)
        guard allowOutside || (result.x >= crop.minX - 1e-8 && result.x <= crop.maxX + 1e-8
            && result.y >= crop.minY - 1e-8 && result.y <= crop.maxY + 1e-8) else { return nil }
        return result
    }

    static func uprightSize(encoded: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: encoded).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    static func angle(a: CGPoint, vertex: CGPoint, b: CGPoint, imageSize: CGSize) -> Double? {
        let u = CGVector(dx: (a.x - vertex.x) * imageSize.width,
                         dy: (a.y - vertex.y) * imageSize.height)
        let v = CGVector(dx: (b.x - vertex.x) * imageSize.width,
                         dy: (b.y - vertex.y) * imageSize.height)
        let length = hypot(u.dx, u.dy) * hypot(v.dx, v.dy)
        guard length > 1e-10 else { return nil }
        return acos(Double(min(1, max(-1, (u.dx * v.dx + u.dy * v.dy) / length)))) * 180 / .pi
    }
}
