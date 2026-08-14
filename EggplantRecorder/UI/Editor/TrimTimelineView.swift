import AppKit
import SwiftUI

struct TrimTimelineView: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    @Binding var current: TimeInterval
    let duration: TimeInterval
    let filmstrip: [NSImage]
    var onSeek: (TimeInterval) -> Void
    var onChangeStart: (TimeInterval) -> Void
    var onChangeEnd: (TimeInterval) -> Void

    @State private var drag: DragKind?

    private let barHeight: CGFloat = 56
    private let handleWidth: CGFloat = 8
    private let playheadWidth: CGFloat = 2
    private let hitSlop: CGFloat = 10

    private enum DragKind {
        case start
        case end
        case playhead
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                filmstripRow(width: width)
                dimmers(width: width)
                selectionStroke(width: width)
                handle(at: x(for: start, width: width))
                handle(at: x(for: end, width: width) - handleWidth)
                playhead(width: width)
            }
            .frame(height: barHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func filmstripRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if filmstrip.isEmpty {
                Rectangle()
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            } else {
                ForEach(Array(filmstrip.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: barHeight)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: barHeight)
    }

    private func dimmers(width: CGFloat) -> some View {
        let startX = x(for: start, width: width)
        let endX = x(for: end, width: width)
        return ZStack(alignment: .leading) {
            Color.black.opacity(0.55)
                .frame(width: max(0, startX), height: barHeight)
            Color.black.opacity(0.55)
                .frame(width: max(0, width - endX), height: barHeight)
                .offset(x: endX)
        }
        .allowsHitTesting(false)
    }

    private func selectionStroke(width: CGFloat) -> some View {
        let startX = x(for: start, width: width)
        let endX = x(for: end, width: width)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color(nsColor: SelectionChrome.blue), lineWidth: 2)
            .frame(width: max(handleWidth * 2, endX - startX), height: barHeight)
            .offset(x: startX)
            .allowsHitTesting(false)
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
            .overlay(
                Capsule()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 2, height: 18)
            )
            .frame(width: handleWidth, height: barHeight)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .offset(x: x)
    }

    private func playhead(width: CGFloat) -> some View {
        let px = x(for: current, width: width)
        return Capsule()
            .fill(Color.white)
            .frame(width: playheadWidth, height: barHeight)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .offset(x: px - playheadWidth / 2)
            .allowsHitTesting(false)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let kind = drag ?? hitKind(at: value.startLocation.x, width: width)
                if drag == nil {
                    drag = kind
                }
                let time = time(for: value.location.x, width: width)
                switch kind {
                case .start:
                    onChangeStart(time)
                case .end:
                    onChangeEnd(time)
                case .playhead:
                    onSeek(time)
                }
            }
            .onEnded { _ in
                drag = nil
            }
    }

    private func hitKind(at locationX: CGFloat, width: CGFloat) -> DragKind {
        let startX = x(for: start, width: width)
        let endX = x(for: end, width: width)
        let playX = x(for: current, width: width)
        let dStart = abs(locationX - startX)
        let dEnd = abs(locationX - endX)
        let dPlay = abs(locationX - playX)
        if dStart <= hitSlop || dEnd <= hitSlop {
            return dStart <= dEnd ? .start : .end
        }
        if dPlay <= hitSlop {
            return .playhead
        }
        if locationX < startX { return .start }
        if locationX > endX { return .end }
        return .playhead
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let ratio = min(max(time / duration, 0), 1)
        return ratio * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0, width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }
}
