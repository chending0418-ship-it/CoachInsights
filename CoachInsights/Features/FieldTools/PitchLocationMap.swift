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
    var ratio: CGFloat = 1.23
    let select: (FieldPoint) -> Void
    static let strikeRect = PitchZone.strikeRect
    static let strikeColor = Theme.burgundy
    static let ballColor = Color(red: 0.22, green: 0.43, blue: 0.34)

    // Historical logs store normalized catcher coordinates in the original strike rectangle.
    // Scale each of the three bands independently so border and out-of-zone hits round-trip.
    static let drawnZone = CGRect(x: 0.23, y: 0.18, width: 0.54, height: 0.64)
    static func project(_ point: FieldPoint, inverse: Bool = false) -> FieldPoint {
        let source = inverse ? drawnZone : strikeRect
        let target = inverse ? strikeRect : drawnZone
        func axis(_ value: Double, _ from: ClosedRange<Double>, _ to: ClosedRange<Double>) -> Double {
            if value <= from.lowerBound { return value / from.lowerBound * to.lowerBound }
            if value >= from.upperBound {
                return to.upperBound + (value - from.upperBound) / (1 - from.upperBound) * (1 - to.upperBound)
            }
            return to.lowerBound + (value - from.lowerBound) / (from.upperBound - from.lowerBound) * (to.upperBound - to.lowerBound)
        }
        return FieldPoint(x: axis(point.x, source.minX...source.maxX, target.minX...target.maxX),
                          y: axis(point.y, source.minY...source.maxY, target.minY...target.maxY))
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
                let field = CGRect(origin: .zero, size: size)
                context.fill(Path(field), with: .color(Color(red: 0.92, green: 0.91, blue: 0.87)))
                let markings = Color(red: 157/255, green: 153/255, blue: 139/255)
                var dots = Path()
                for column in 0..<25 {
                    for row in 0..<25 {
                        let center = p(Double(column) * 0.04 + 0.02, Double(row) * 0.04 + 0.02)
                        dots.addEllipse(in: CGRect(x: center.x, y: center.y, width: size.width * 0.0042, height: size.height * 0.0042))
                    }
                }
                context.fill(dots, with: .color(markings.opacity(0.75)))
                var ticks = Path()
                for i in 1..<20 {
                    let at = Double(i) / 20
                    let length = i.isMultiple(of: 2) ? 0.023 : 0.0125
                    ticks.move(to: p(at, 0)); ticks.addLine(to: p(at, length))
                    ticks.move(to: p(0, at)); ticks.addLine(to: p(length, at))
                    ticks.move(to: p(1, at)); ticks.addLine(to: p(1 - length, at))
                }
                context.stroke(ticks, with: .color(markings), lineWidth: 0.8)
                var guides = Path()
                guides.move(to: p(0.5, 0)); guides.addLine(to: p(0.5, 0.16))
                guides.move(to: p(0.5, 0.84)); guides.addLine(to: p(0.5, 1))
                guides.move(to: p(0, 0.5)); guides.addLine(to: p(0.21, 0.5))
                guides.move(to: p(0.79, 0.5)); guides.addLine(to: p(1, 0.5))
                context.stroke(guides, with: .color(markings), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
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
                let rect = CGRect(x: size.width * Self.drawnZone.minX, y: size.height * Self.drawnZone.minY,
                                  width: size.width * Self.drawnZone.width, height: size.height * Self.drawnZone.height)
                context.fill(Path(rect), with: .color(Color(red: 250/255, green: 248/255, blue: 238/255)))
                context.stroke(Path(rect), with: .color(Color(red: 0.18, green: 0.25, blue: 0.23).opacity(0.8)), lineWidth: 1.8)
                var corners = Path()
                for x in [rect.minX, rect.maxX] {
                    for y in [rect.minY, rect.maxY] {
                        corners.move(to: CGPoint(x: x + (x == rect.minX ? 1 : -1) * rect.width * 0.11, y: y))
                        corners.addLine(to: CGPoint(x: x, y: y))
                        corners.addLine(to: CGPoint(x: x, y: y + (y == rect.minY ? 1 : -1) * rect.height * 0.094))
                    }
                }
                context.stroke(corners, with: .color(Notebook.ink), lineWidth: max(1.4, size.width * 0.01))
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
                    let mark = pitches[index], point = Self.project(viewpoint.transform(mark.point))
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
                let touch = FieldPoint(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height)
                select(viewpoint.transform(Self.project(touch, inverse: true)))
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
