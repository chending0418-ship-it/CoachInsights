import SwiftUI

/// Fixed-ratio catcher-view diagram. Coordinates describe manual marks on this
/// diagram, independent of screen size; they do not imply measured trajectories.
struct PitchLocationMap: View {
    var pitches: [PitchMark]
    var correcting = false
    var sequence = 1
    let select: (FieldPoint) -> Void
    static let strikeRect = PitchZone.strikeRect
    static let strikeColor = Color(red: 0.71, green: 0.23, blue: 0.29)
    static let ballColor = Color(red: 0.22, green: 0.43, blue: 0.34)

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
                let field = CGRect(origin: .zero, size: size)
                context.fill(Path(field), with: .color(Color(red: 0.81, green: 0.85, blue: 0.79)))
                // Quiet field perspective gives the strike zone a spatial anchor.
                let dirt = Path { path in
                    path.move(to: p(0, 0.72)); path.addQuadCurve(to: p(1, 0.72), control: p(0.5, 0.48))
                    path.addLine(to: p(1, 1)); path.addLine(to: p(0, 1)); path.closeSubpath()
                }
                context.fill(dirt, with: .color(Color(red: 0.88, green: 0.83, blue: 0.73)))
                var lanes = Path(); lanes.move(to: p(0, 0.55)); lanes.addLine(to: p(0.5, 0.93)); lanes.addLine(to: p(1, 0.55))
                context.stroke(lanes, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
                let mound = Path(ellipseIn: CGRect(x: size.width * 0.42, y: size.height * 0.13, width: size.width * 0.16, height: size.height * 0.045))
                context.fill(mound, with: .color(Color(red: 0.80, green: 0.73, blue: 0.61)))
                let plate = Path { path in
                    path.move(to: p(0.45, 0.86)); path.addLine(to: p(0.55, 0.86)); path.addLine(to: p(0.55, 0.90))
                    path.addLine(to: p(0.50, 0.94)); path.addLine(to: p(0.45, 0.90)); path.closeSubpath()
                }
                context.fill(plate, with: .color(.white.opacity(0.9)))
                let rect = CGRect(x: size.width * Self.strikeRect.minX, y: size.height * Self.strikeRect.minY,
                                  width: size.width * Self.strikeRect.width, height: size.height * Self.strikeRect.height)
                context.fill(Path(rect), with: .color(.white.opacity(0.36)))
                context.stroke(Path(rect), with: .color(Color(red: 0.18, green: 0.25, blue: 0.23).opacity(0.8)), lineWidth: 1.8)
                var grid = Path()
                for index in 1...2 {
                    let x = rect.minX + rect.width * Double(index) / 3
                    let y = rect.minY + rect.height * Double(index) / 3
                    grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                    grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                context.stroke(grid, with: .color(Color(red: 0.18, green: 0.25, blue: 0.23).opacity(0.42)), lineWidth: 1)
                for index in pitches.indices.suffix(30) {
                    let mark = pitches[index], point = mark.point
                    let radius: CGFloat = min(15, max(11, size.width * 0.032))
                    let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(circle, with: .color(mark.isStrike ? Self.strikeColor : Self.ballColor))
                    context.stroke(circle, with: .color(.white.opacity(0.95)), lineWidth: 1.8)
                    let number = correcting ? sequence : index + 1
                    let textSize = min(radius * 0.88, radius * 3.3 / CGFloat(String(number).count))
                    context.draw(Text("\(number)").font(.system(size: textSize, weight: .bold)).foregroundColor(.white), at: center)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                select(FieldPoint(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height))
                UISelectionFeedbackGenerator().selectionChanged()
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(correcting ? "修正投球落点图" : "投球落点图")
            .accessibilityValue("捕手视角，手动记录，\(pitches.count) 球")
            .accessibilityIdentifier("pitchMap")
            .accessibilityActions {
                ForEach(PitchZone.allCases, id: \.self) { zone in
                    Button((correcting ? "移动至" : "记录") + zone.title) { select(zone.point) }
                }
            }
        }
        .aspectRatio(1.04, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            Text(correcting ? "点击移动这一球" : "点击记录落点").font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.85), in: Capsule()).padding(12).allowsHitTesting(false)
        }
    }
}
