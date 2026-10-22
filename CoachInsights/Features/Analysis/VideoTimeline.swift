import SwiftUI

/// Time-based coarse and fine scrubbing; no assumptions about constant source frame rate.
struct VideoTimeline:View {
    @ObservedObject var workspace:AnalysisWorkspace
    var compact=false
    @State private var fineOrigin:Double?
    @State private var showClip=false
    private var w:AnalysisWorkspace { workspace }
    var body:some View {
        VStack(spacing:2) {
            if !compact && !w.thumbnails.isEmpty {
                GeometryReader { g in
                    HStack(spacing:1) { ForEach(w.thumbnails.indices,id:\.self) { index in
                        Image(uiImage:w.thumbnails[index]).resizable().scaledToFill().frame(width:max(1,g.size.width/CGFloat(w.thumbnails.count)),height:28).clipped()
                    } }.clipShape(RoundedRectangle(cornerRadius:4))
                }.frame(height:28).allowsHitTesting(false)
            }
            if let metadata=w.metadata {
                let duration=max(0.001,metadata.timeline.duration.seconds)
                ZStack(alignment:.topLeading) {
                    Slider(value:Binding(get:{w.time},set:{w.scrub(to:$0)}),in:0...duration,onEditingChanged:{editing in if editing { w.beginScrubbing() } else { w.endScrubbing() } }).accessibilityIdentifier("frameSlider").tint(Theme.rose)
                    GeometryReader { g in
                        ForEach(w.snapshot.keyframes.filter{$0.videoID==w.selectedVideoID}) { keyframe in
                            Circle().fill(.yellow).frame(width:5,height:5).position(x:g.size.width*keyframe.time.seconds/duration,y:3)
                        }
                    }.allowsHitTesting(false)
                }.frame(height:30)
                if !compact {
                    GeometryReader { g in
                        ZStack {
                            Canvas { ctx,size in
                                for i in 0...40 {
                                    let x=CGFloat(i)*size.width/40
                                    let height:CGFloat=i%5==0 ? 16:8
                                    ctx.stroke(Path { p in p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:height)) },with:.color(.gray),lineWidth:1)
                                }
                            }
                            Rectangle().fill(Theme.rose).frame(width:2,height:22)
                        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            if fineOrigin == nil { fineOrigin=w.time;w.beginScrubbing() }
                            // The full strip spans two seconds, even for a long source.
                            w.scrub(to:(fineOrigin ?? w.time)+Double(value.translation.width/max(1,g.size.width))*2)
                        }.onEnded { _ in fineOrigin=nil;w.endScrubbing() })
                    }.frame(height:24).accessibilityLabel("精细定位，向左右拖动").accessibilityIdentifier("fineTimeline")
                    HStack(spacing:8) {
                        Menu("片段 \(w.clip.start.seconds.formatted(.number.precision(.fractionLength(2))))–\(w.clip.end.seconds.formatted(.number.precision(.fractionLength(2))))s") {
                            Button("当前帧设为起点") { w.pause();w.markStart() }
                            Button("当前帧设为终点") { w.pause();w.markEnd() }
                            Button("恢复完整视频") { w.fullClip() }
                            Button("调整片段范围") { w.pause();showClip=true }
                        }.font(.caption2).accessibilityIdentifier("clipMenu")
                        GeometryReader { g in
                            Capsule().fill(.gray.opacity(0.3))
                            Capsule().fill(Theme.rose).frame(width:max(2,g.size.width*(w.clip.end.seconds-w.clip.start.seconds)/duration)).offset(x:g.size.width*w.clip.start.seconds/duration)
                        }.frame(height:4)
                    }
                }
            }
        }.sheet(isPresented:$showClip) {
            NavigationStack {
                Form {
                    if let map=w.metadata?.timeline,let bounds=map.frameBounds(in:w.clip) {
                        Section("拖动调整片段") {
                            Text("起点 \(w.clip.start.seconds,specifier:"%.3f") s")
                            Slider(value:Binding(get:{Double(bounds.lowerBound)},set:{w.setClipBoundary(frame:Int($0),start:true)}),in:0...Double(max(1,map.frames.count-1)),step:1,onEditingChanged:{if !$0 { w.save() }}).accessibilityIdentifier("clipStartSlider")
                            Text("终点 \(w.clip.end.seconds,specifier:"%.3f") s")
                            Slider(value:Binding(get:{Double(bounds.upperBound)},set:{w.setClipBoundary(frame:Int($0),start:false)}),in:0...Double(max(1,map.frames.count-1)),step:1,onEditingChanged:{if !$0 { w.save() }}).accessibilityIdentifier("clipEndSlider")
                            Text("最短保留一个源帧，原视频不会被裁掉。").font(.caption).foregroundStyle(.secondary)
                            Button("恢复完整视频") { w.fullClip() }
                        }
                    }
                }.navigationTitle("片段范围").toolbar { Button("完成") { w.save();showClip=false } }
            }.presentationDetents([.medium]).preferredColorScheme(.dark)
        }
    }
}

/// A touch-down starts a single step. Holding repeats; releasing/cancelling stops immediately.
struct FrameStepButton:View {
    let direction:Int
    let step:()->Void
    @Environment(\.scenePhase) private var phase
    @State private var repeating:Task<Void,Never>?
    @State private var pressed=false
    var body:some View {
        Image(systemName:direction<0 ? "backward.end.fill":"forward.end.fill")
            .frame(width:44,height:44).contentShape(Rectangle())
            .foregroundStyle(pressed ? Theme.rose:.white)
            .gesture(DragGesture(minimumDistance:0).onChanged { value in
                guard !pressed else { return };pressed=true;step()
                repeating=Task { @MainActor in
                    do {
                        try await Task.sleep(for:.milliseconds(350))
                        while !Task.isCancelled { step();try await Task.sleep(for:.milliseconds(90)) }
                    } catch {}
                }
            }.onEnded { _ in stop() })
            .onDisappear { stop() }.onChange(of:phase) { _,value in if value != .active { stop() } }
            .accessibilityElement().accessibilityAddTraits(.isButton)
            .accessibilityLabel(direction<0 ? "前一帧":"后一帧").accessibilityAction { step() }
    }
    private func stop() { repeating?.cancel();repeating=nil;pressed=false }
}
