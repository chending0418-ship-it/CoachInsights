import SwiftUI

/// Fixed-ratio diagram with canonical catcher coordinates. Coordinates describe manual marks on this
/// diagram, independent of screen size; they do not imply measured trajectories.
struct PitchLocationMap: View {
    var pitches: [PitchMark]
    var viewpoint: PitchViewpoint = .catcher
    var readOnly = false
    var correcting = false
    var sequence = 1
    var selectedIndex: Int?
    var ratio: CGFloat = 1.04
    let select: (FieldPoint) -> Void
    static let strikeRect = PitchZone.strikeRect
    static let strikeColor = Theme.burgundy
    static let ballColor = Color(red: 0.22, green: 0.43, blue: 0.34)

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
                let field = CGRect(origin: .zero, size: size)
                context.fill(Path(field), with: .color(Color(red: 0.92, green: 0.91, blue: 0.87)))
                var dots = Path()
                for x in stride(from: 5.0, to: size.width, by: 12) {
                    for y in stride(from: 5.0, to: size.height, by: 12) {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                context.fill(dots, with: .color(.secondary.opacity(0.45)))
                func platePoint(_ x: Double, _ y: Double) -> CGPoint {
                    p(x, viewpoint == .catcher ? y : 1 - y)
                }
                let plate = Path { path in
                    path.move(to: platePoint(0.45, 0.90)); path.addLine(to: platePoint(0.55, 0.90))
                    path.addLine(to: platePoint(0.55, 0.93)); path.addLine(to: platePoint(0.50, 0.97))
                    path.addLine(to: platePoint(0.45, 0.93)); path.closeSubpath()
                }
                context.fill(plate, with: .color(.white))
                context.stroke(plate, with: .color(.secondary), lineWidth: 1.5)
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
                let visible = Array(pitches.indices.suffix(30)).filter { $0 != selectedIndex }
                let highlighted = selectedIndex.flatMap { pitches.indices.contains($0) ? [$0] : nil } ?? []
                for index in visible + highlighted {
                    let mark = pitches[index], point = viewpoint.transform(mark.point)
                    let radius: CGFloat = min(15, max(11, size.width * 0.032))
                    let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    var markerContext = context
                    if selectedIndex != nil && index != selectedIndex { markerContext.opacity = 0.55 }
                    markerContext.fill(circle, with: .color(mark.isStrike ? Theme.burgundy : .white))
                    markerContext.stroke(circle, with: .color(mark.isStrike ? .white : Self.ballColor), lineWidth: 1.8)
                    if index == selectedIndex {
                        context.stroke(Path(ellipseIn: circle.boundingRect.insetBy(dx: -3, dy: -3)), with: .color(Notebook.ink), lineWidth: 2)
                    }
                    let number = correcting && pitches.count == 1 ? sequence : index + 1
                    let textSize = min(radius * 0.88, radius * 3.3 / CGFloat(String(number).count))
                    markerContext.draw(Text("\(number)").font(.system(size: textSize, weight: .bold)).foregroundColor(mark.isStrike ? .white : Self.ballColor), at: center)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                guard !readOnly else { return }
                select(viewpoint.transform(FieldPoint(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height)))
                UISelectionFeedbackGenerator().selectionChanged()
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(readOnly ? "投球回看图" : correcting ? "修正投球落点图" : "投球落点图")
            .accessibilityValue("\(viewpoint.title)，手动记录，\(pitches.count) 球")
            .accessibilityIdentifier("pitchMap")
            .accessibilityActions {
                ForEach(readOnly ? [] : PitchZone.allCases, id: \.self) { zone in
                    Button((correcting ? "移动至" : "记录") + zone.title) { select(viewpoint.transform(zone.point)) }
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
