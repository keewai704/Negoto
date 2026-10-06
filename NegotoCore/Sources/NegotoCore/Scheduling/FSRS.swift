import Foundation

/// FSRS memory model (versions 4.5, 5 and 6, selected by the number of parameters), used when the
/// imported collection has FSRS enabled.
public struct FSRS: Sendable {
    public var w: [Double]
    public var desiredRetention: Double

    public static let defaultParams6: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835,
        0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    public init?(params: [Double], desiredRetention: Double) {
        var p = params
        if p.isEmpty { p = Self.defaultParams6 }
        guard p.count == 17 || p.count == 19 || p.count == 21 else { return nil }
        w = p
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.99)
    }

    var version: Int { w.count >= 21 ? 6 : (w.count >= 19 ? 5 : 4) }
    var decay: Double { version == 6 ? -w[20] : -0.5 }
    var factor: Double { pow(0.9, 1 / decay) - 1 }

    public func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + factor * t / max(s, 0.001), decay)
    }

    public func interval(stability s: Double) -> Double {
        s / factor * (pow(desiredRetention, 1 / decay) - 1)
    }

    func initStability(_ g: Rating) -> Double { max(w[g.rawValue - 1], 0.001) }

    func initDifficulty(_ g: Rating) -> Double {
        let g = Double(g.rawValue)
        if version == 4 { return clampD(w[4] - w[5] * (g - 3)) }
        return clampD(w[4] - exp(w[5] * (g - 1)) + 1)
    }

    private func clampD(_ d: Double) -> Double { min(max(d, 1), 10) }

    func nextDifficulty(_ d: Double, _ g: Rating) -> Double {
        let g = Double(g.rawValue)
        if version == 4 {
            let next = d - w[6] * (g - 3)
            return clampD(w[7] * w[4] + (1 - w[7]) * next)
        }
        let delta = -w[6] * (g - 3)
        let next = d + delta * (10 - d) / 9
        let d0Easy = w[4] - exp(w[5] * 3) + 1
        return clampD(w[7] * d0Easy + (1 - w[7]) * next)
    }

    func successStability(_ d: Double, _ s: Double, _ r: Double, _ g: Rating) -> Double {
        let hard = g == .hard ? w[15] : 1
        let easy = g == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy)
    }

    func failStability(_ d: Double, _ s: Double, _ r: Double) -> Double {
        let f = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
        if version >= 5 { return min(f, s / exp(w[17] * w[18])) }
        return f
    }

    func shortTermStability(_ s: Double, _ g: Rating) -> Double {
        let gv = Double(g.rawValue)
        if version == 6 {
            var sinc = exp(w[17] * (gv - 3 + w[18])) * pow(s, -w[19])
            if g.rawValue >= 2 { sinc = max(sinc, 1) }
            return s * sinc
        }
        var next = s * exp(w[17] * (gv - 3 + w[18]))
        if g.rawValue >= 3 { next = max(next, s) }
        return next
    }

    /// Converts an SM-2 card into an approximate memory state (as Anki does for cards without history).
    func memoryFromSM2(easeFactor: Double, interval: Double, retention: Double = 0.9) -> MemoryState {
        let s = max(interval, 0.1) * factor / (pow(retention, 1 / decay) - 1)
        let denom = exp(w[8]) * pow(s, -w[9]) * (exp((1 - retention) * w[10]) - 1)
        let d = denom > 0 ? 11 - (easeFactor - 1) / denom : 5
        return MemoryState(stability: s, difficulty: clampD(d))
    }

    func next(_ memory: MemoryState?, elapsedDays: Double) -> FSRSNextMemory {
        func state(_ g: Rating) -> MemoryState {
            guard let m = memory else { return MemoryState(stability: initStability(g), difficulty: initDifficulty(g)) }
            let d = nextDifficulty(m.difficulty, g)
            let s: Double
            if elapsedDays < 1 && version >= 5 {
                s = shortTermStability(m.stability, g)
            } else {
                let r = retrievability(elapsedDays: elapsedDays, stability: m.stability)
                s = g == .again ? failStability(m.difficulty, m.stability, r) : successStability(m.difficulty, m.stability, r, g)
            }
            return MemoryState(stability: min(max(s, 0.001), 36500), difficulty: d)
        }
        return FSRSNextMemory(fsrs: self, again: state(.again), hard: state(.hard), good: state(.good), easy: state(.easy))
    }

    func nextMemory(card: Card, state: CardState, today: Int, elapsedOverride: Int?) -> FSRSNextMemory? {
        var memory: MemoryState? = card.memoryState.map { MemoryState(stability: $0.stability, difficulty: $0.difficulty) }
        var elapsed = 0
        switch state {
        case .new:
            memory = nil
        case .review(let r):
            elapsed = r.elapsedDays
            if memory == nil { memory = memoryFromSM2(easeFactor: r.easeFactor, interval: Double(r.scheduledDays)) }
        case .relearning(_, let r):
            if memory == nil { memory = memoryFromSM2(easeFactor: r.easeFactor, interval: Double(r.scheduledDays)) }
        case .learning:
            break
        }
        if let elapsedOverride, memory != nil { elapsed = elapsedOverride }
        return next(memory, elapsedDays: Double(elapsed))
    }
}

struct FSRSNextMemory {
    var fsrs: FSRS
    var again: MemoryState
    var hard: MemoryState
    var good: MemoryState
    var easy: MemoryState

    func interval(_ rating: Rating, _ ctx: SchedulerContext) -> Int {
        let m: MemoryState
        switch rating {
        case .again: m = again
        case .hard: m = hard
        case .good: m = good
        case .easy: m = easy
        }
        let days = Int(fsrs.interval(stability: m.stability).rounded())
        return min(max(days, 1), max(ctx.config.maximumReviewInterval, 1))
    }
}
