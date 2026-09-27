import Foundation
import CoreGraphics

/// Observes pointer position only for the duration of a picking session.
/// Reading the position directly also works when a transparent panel or a menu
/// does not deliver mouse-moved events to the overlay's content view.
public final class PointerTracker {
    private let readPosition: () -> CGPoint
    private let onChange: (CGPoint) -> Void
    private let onTick: (CGPoint) -> Void
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastPosition: CGPoint?

    public init(interval: TimeInterval = 1.0 / 60,
                readPosition: @escaping () -> CGPoint,
                onTick: @escaping (CGPoint) -> Void = { _ in },
                onChange: @escaping (CGPoint) -> Void) {
        self.interval = interval
        self.readPosition = readPosition
        self.onChange = onChange
        self.onTick = onTick
    }

    public func start() {
        precondition(Thread.isMainThread)
        guard timer == nil else { return }
        lastPosition = nil
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.15
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        tick()
    }

    public func stop() {
        precondition(Thread.isMainThread)
        timer?.invalidate()
        timer = nil
        lastPosition = nil
    }

    private func tick() {
        guard timer != nil else { return }
        let position = readPosition()
        onTick(position)
        guard position != lastPosition else { return }
        lastPosition = position
        onChange(position)
    }

    deinit { timer?.invalidate() }
}
