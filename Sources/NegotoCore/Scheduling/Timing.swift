import Foundation

/// Mirrors Anki's `sched_timing_today`: which "day number" it is for the collection and when
/// the next day starts, honouring the user's rollover hour ("next day starts at").
public struct SchedTimingToday: Equatable, Sendable {
    public var daysElapsed: Int
    public var nextDayAt: Int64

    public static func compute(creationSecs: Int64, creationOffsetMinutesWest: Int?, nowSecs: Int64,
                               timeZone: TimeZone = .current, rolloverHour: Int, schedulerVersion: Int) -> SchedTimingToday {
        if schedulerVersion < 2 {
            // v1: days since creation, where creation time already sits on the rollover boundary.
            let days = Int((nowSecs - creationSecs) / 86400)
            let next = creationSecs + Int64(days + 1) * 86400
            return SchedTimingToday(daysElapsed: max(0, days), nextDayAt: next)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let now = Date(timeIntervalSince1970: TimeInterval(nowSecs))

        var createdCal = Calendar(identifier: .gregorian)
        if let west = creationOffsetMinutesWest, let tz = TimeZone(secondsFromGMT: -west * 60) {
            createdCal.timeZone = tz
        } else {
            createdCal.timeZone = timeZone
        }
        let created = Date(timeIntervalSince1970: TimeInterval(creationSecs))
        let createdComps = createdCal.dateComponents([.year, .month, .day], from: created)

        let nowComps = cal.dateComponents([.year, .month, .day], from: now)
        var rolloverComps = nowComps
        rolloverComps.hour = rolloverHour
        let rolloverToday = cal.date(from: rolloverComps) ?? now
        let rolloverPassed = rolloverToday <= now
        let nextDay = rolloverPassed ? (cal.date(byAdding: .day, value: 1, to: rolloverToday) ?? rolloverToday) : rolloverToday

        // Count calendar days between the two local dates.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let startDate = utc.date(from: DateComponents(year: createdComps.year, month: createdComps.month, day: createdComps.day)) ?? created
        let endDate = utc.date(from: DateComponents(year: nowComps.year, month: nowComps.month, day: nowComps.day)) ?? now
        var days = utc.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        if !rolloverPassed { days -= 1 }
        return SchedTimingToday(daysElapsed: max(0, days), nextDayAt: Int64(nextDay.timeIntervalSince1970))
    }
}

public extension AnkiCollection {
    func timingToday(now: Date = Date(), timeZone: TimeZone = .current) -> SchedTimingToday {
        SchedTimingToday.compute(creationSecs: creationTime, creationOffsetMinutesWest: creationOffset,
                                 nowSecs: Int64(now.timeIntervalSince1970), timeZone: timeZone,
                                 rolloverHour: rolloverHour, schedulerVersion: schedulerVersion)
    }
}
