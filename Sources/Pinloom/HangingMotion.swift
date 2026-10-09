import SwiftUI

/// A damped pendulum driven by changes in the clip's horizontal velocity.
/// Positions are independent of this transient motion and remain exact.
struct HangingDynamics {
    private(set) var angle: Double = 0
    private(set) var angularVelocity: Double = 0
    private(set) var anchorVelocity: Double = 0
    var length: Double = 90

    var settled: Bool { abs(angle) < 0.0005 && abs(angularVelocity) < 0.003 }

    mutating func drive(velocity: Double) {
        guard velocity.isFinite else { return }
        let bounded = max(-1800, min(1800, velocity))
        angularVelocity += (bounded - anchorVelocity) * 0.45 / max(60, length)
        angularVelocity = max(-6, min(6, angularVelocity))
        anchorVelocity = bounded
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        // Substeps keep the spring stable if a frame is delayed.
        var remaining = min(elapsed, 0.1)
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240)
            angularVelocity += (-3200 / max(60, length) * sin(angle) - 3.8 * angularVelocity) * dt
            angle += angularVelocity * dt
            if abs(angle) > 0.42 {
                angle = max(-0.42, min(0.42, angle))
                angularVelocity *= -0.15
            }
            remaining -= dt
        }
        if settled { angle = 0; angularVelocity = 0 }
    }
}

@MainActor
final class HangingMotion: ObservableObject {
    @Published private(set) var degrees: Double = 0
    private var dynamics = HangingDynamics()
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var lastSample: (point: CGPoint, time: TimeInterval)?
    private var moving = false

    func begin(at point: CGPoint, length: CGFloat) {
        dynamics.length = max(60, Double(length))
        moving = true
        lastSample = (point, ProcessInfo.processInfo.systemUptime)
        startTimer()
    }

    func move(to point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let sample = lastSample else { return }
        let dt = max(1.0 / 120, now - sample.time)
        let velocity = Double(point.x - sample.point.x) / dt
        let response = 1 - exp(-dt / 0.045)
        dynamics.drive(velocity: dynamics.anchorVelocity + (velocity - dynamics.anchorVelocity) * response)
        lastSample = (point, now)
    }

    func release() {
        moving = false
        lastSample = nil
        dynamics.drive(velocity: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSample = nil
        moving = false
        dynamics = HangingDynamics()
        degrees = 0
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        if moving, let sample = lastSample, now - sample.time > 0.06 {
            dynamics.drive(velocity: dynamics.anchorVelocity * exp(-elapsed / 0.06))
        }
        dynamics.advance(by: elapsed)
        degrees = dynamics.angle * 180 / .pi
        if !moving && dynamics.settled { stop() }
    }
}
