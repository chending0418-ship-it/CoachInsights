import SwiftUI

struct BattingContactIcon: View {
    let contact: BattingContact

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 92, size.height / 56)
            context.translateBy(x: (size.width - 92 * scale) / 2, y: (size.height - 56 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 4, y: 48))
            baseline.addLine(to: CGPoint(x: 87, y: 48))
            context.stroke(baseline, with: .color(Notebook.rule), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            var path = Path()
            path.move(to: contact == .miss ? CGPoint(x: 10, y: 45) : CGPoint(x: 7, y: 47))
            let end: CGPoint
            switch contact {
            case .ground:
                path.addQuadCurve(to: CGPoint(x: 29, y: 45), control: CGPoint(x: 19, y: 21))
                path.addQuadCurve(to: CGPoint(x: 46, y: 45), control: CGPoint(x: 38, y: 29))
                path.addQuadCurve(to: CGPoint(x: 60, y: 46), control: CGPoint(x: 53, y: 37))
                end = CGPoint(x: 82, y: 46)
                path.addLine(to: end)
            case .line:
                end = CGPoint(x: 79, y: 15)
                path.addQuadCurve(to: end, control: CGPoint(x: 30, y: 19))
            case .fly:
                end = CGPoint(x: 78, y: 39)
                path.addQuadCurve(to: end, control: CGPoint(x: 43, y: -15))
            case .miss:
                end = CGPoint(x: 78, y: 16)
                path.addQuadCurve(to: CGPoint(x: 57, y: 21), control: CGPoint(x: 31, y: 23))
            }
            let ink: Color = contact == .fly || contact == .ground ? Notebook.fieldGreen : Theme.burgundy
            context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 2.1, dash: contact == .miss ? [4, 4] : []))
            let ball = Path(ellipseIn: CGRect(x: end.x - 3.3, y: end.y - 3.3, width: 6.6, height: 6.6))
            if contact != .miss { context.fill(ball, with: .color(ink)) }
            context.stroke(ball, with: .color(ink), lineWidth: 1.3)
        }.aspectRatio(92.0 / 56, contentMode: .fit).accessibilityHidden(true)
    }
}
