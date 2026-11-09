import SwiftUI

struct BattingContactIcon: View {
    let contact: BattingContact

    var body: some View {
        Canvas { context, _ in
            let ground = Path { path in
                path.move(to: CGPoint(x: 2, y: 24))
                path.addLine(to: CGPoint(x: 30, y: 24))
            }
            context.stroke(ground, with: .color(Theme.burgundy.opacity(0.32)), lineWidth: 1)
            let destination: CGPoint
            let control: CGPoint
            switch contact {
            case .ground:
                destination = CGPoint(x: 27, y: 21)
                control = CGPoint(x: 12, y: 24)
            case .line:
                destination = CGPoint(x: 27, y: 12)
                control = CGPoint(x: 15, y: 14)
            case .fly:
                destination = CGPoint(x: 27, y: 10)
                control = CGPoint(x: 13, y: -3)
            case .miss:
                destination = CGPoint(x: 26, y: 18)
                control = CGPoint(x: 15, y: 27)
            }
            let trajectory = Path { path in
                path.move(to: CGPoint(x: 3, y: 19))
                path.addQuadCurve(to: destination, control: control)
            }
            context.stroke(trajectory, with: .foreground, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [2, 3]))
            if contact == .miss {
                let cross = Path { path in
                    path.move(to: CGPoint(x: 22, y: 5)); path.addLine(to: CGPoint(x: 28, y: 11))
                    path.move(to: CGPoint(x: 28, y: 5)); path.addLine(to: CGPoint(x: 22, y: 11))
                }
                context.stroke(cross, with: .foreground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            } else {
                let ball = CGRect(x: destination.x - 2.5, y: destination.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: ball), with: .foreground)
            }
        }.frame(width: 32, height: 28).accessibilityHidden(true)
    }
}
