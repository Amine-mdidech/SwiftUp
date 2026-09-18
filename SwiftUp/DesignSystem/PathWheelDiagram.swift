import SwiftUI

/// The radial "wheel" of track nodes around a center grade-progress hub. This is a from-scratch
/// layout, not a copy of the source design's hand-positioned 5-node mockup — that doesn't
/// generalize to grades with 4 or 6 tracks. N nodes are spaced evenly on a circle starting at
/// 12 o'clock going clockwise, with spokes to the hub styled per each track's state.
struct PathWheelDiagram: View {
    let tracks: [PathTrack]
    let grade: SkillLevel
    let pathRepo: PathRepository
    let onSelectTrack: (PathTrack) -> Void

    private let canvasSize: CGFloat = 300
    private let hubDiameter: CGFloat = 80
    private let nodeDiameter: CGFloat = 60
    private let nodeRadius: CGFloat = 110

    private var center: CGPoint { CGPoint(x: canvasSize / 2, y: canvasSize / 2) }
    private var closedCount: Int { tracks.filter(pathRepo.isTrackClosed).count }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for (index, track) in tracks.enumerated() {
                    guard !pathRepo.isTrackClosed(track) else { continue } // no spoke to a cleared track
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: nodePosition(at: index))
                    if pathRepo.isTrackReachable(track) {
                        context.stroke(line, with: .color(Theme.Colors.text), lineWidth: 2)
                    } else {
                        context.stroke(line, with: .color(Theme.Colors.neutral400), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }

                let hubRect = CGRect(x: center.x - hubDiameter / 2, y: center.y - hubDiameter / 2, width: hubDiameter, height: hubDiameter)
                context.stroke(Path(ellipseIn: hubRect), with: .color(Theme.Colors.neutral200), lineWidth: 5)
                if !tracks.isEmpty {
                    let fraction = Double(closedCount) / Double(tracks.count)
                    var ring = Path()
                    ring.addArc(center: center, radius: hubDiameter / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
                    context.stroke(ring, with: .color(Theme.Colors.accent), lineWidth: 5)
                }
            }
            .frame(width: canvasSize, height: canvasSize)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                nodeView(for: track)
                    .position(nodePosition(at: index))
            }

            VStack(spacing: 1) {
                Text(grade.next?.rawValue ?? "—")
                    .font(Theme.Fonts.heading(12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(closedCount) of \(tracks.count)")
                    .font(.system(size: 9))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .frame(width: hubDiameter - 8, height: hubDiameter - 8)
            .background(Theme.Colors.bg)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.Colors.neutral400, style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
            .position(center)
        }
        .frame(width: canvasSize, height: canvasSize)
    }

    // Not `private`: `SwiftUpTests` (`@testable import`) calls this directly rather than
    // maintaining a duplicate copy of the formula. Still not part of any public API surface.
    func nodePosition(at index: Int) -> CGPoint {
        guard !tracks.isEmpty else { return center }
        let angle = Angle.degrees(-90 + Double(index) * (360.0 / Double(tracks.count)))
        return CGPoint(
            x: center.x + nodeRadius * cos(angle.radians),
            y: center.y + nodeRadius * sin(angle.radians)
        )
    }

    @ViewBuilder
    private func nodeView(for track: PathTrack) -> some View {
        let closed = pathRepo.isTrackClosed(track)
        let reachable = pathRepo.isTrackReachable(track)
        Button {
            onSelectTrack(track)
        } label: {
            VStack(spacing: 1) {
                if closed {
                    Text("✓").font(Theme.Fonts.heading(20))
                } else {
                    Text(String(format: "%02d", track.order)).font(Theme.Fonts.heading(17))
                }
                if reachable && !closed {
                    let doneStages = track.stages.filter(pathRepo.isStageCompleted).count
                    Text("\(doneStages)/\(track.stages.count)").font(.system(size: 9.5))
                }
            }
            .frame(width: nodeDiameter, height: nodeDiameter)
            .background(nodeBackground(closed: closed, reachable: reachable))
            .foregroundStyle(nodeForeground(closed: closed, reachable: reachable))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(reachable && !closed ? Theme.Colors.accent : Color.clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(!reachable)
    }

    private func nodeBackground(closed: Bool, reachable: Bool) -> Color {
        if closed { return Theme.Colors.text }
        if reachable { return Theme.Colors.accent100 }
        return Theme.Colors.neutral200
    }

    private func nodeForeground(closed: Bool, reachable: Bool) -> Color {
        if closed { return Theme.Colors.bg }
        if reachable { return Theme.Colors.accent700 }
        return Theme.Colors.neutral700
    }
}

#Preview {
    let repo = PathRepository.preview()
    let tracks = repo.tracks(for: .junior)
    return PathWheelDiagram(tracks: tracks, grade: .junior, pathRepo: repo, onSelectTrack: { _ in })
        .padding()
        .background(Theme.Colors.bg)
}
