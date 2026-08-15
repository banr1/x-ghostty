import Foundation

/// A *workday*: the local-time span from 06:00 to the next day's 06:00
/// (`SPEC.md` §28.1).
///
/// This is the unit the daily priority reset counts in. Priority means "today's
/// focus", so it is rebuilt every morning rather than kept as a permanent
/// attribute; the boundary sits at 06:00 rather than midnight so a session that
/// runs past midnight still belongs to the day it started in.
///
/// The value is a plain calendar date — the date of the workday's *start* — so
/// two moments belong to the same workday exactly when their `Workday` values
/// are equal. That makes the "once per workday" rule a single equality check.
struct Workday: Codable, Equatable, Hashable {
    /// The local hour the workday flips over at.
    static var boundaryHour: Int { 6 }

    let year: Int
    let month: Int
    let day: Int

    /// The workday `date` falls in: its own calendar date from 06:00 onwards,
    /// the previous calendar date before that.
    ///
    /// The rollback uses calendar arithmetic rather than subtracting six hours
    /// of wall time, so a DST transition between the boundary and `date` cannot
    /// shift the result by a day.
    init(containing date: Date, calendar: Calendar = .current) {
        let startOfWorkday = calendar.component(.hour, from: date) < Self.boundaryHour
            ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date)
            : date
        let components = calendar.dateComponents([.year, .month, .day], from: startOfWorkday)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    /// The first moment after `date` at which the workday flips over — the next
    /// local 06:00 (`SPEC.md` §28.3).
    ///
    /// This is what a running app schedules its reset check against, so the
    /// "when" of the boundary stays in the model with the "which day" of it.
    /// Resolved through the calendar rather than by adding a fixed number of
    /// seconds, so a DST transition moves the boundary with the wall clock
    /// instead of landing an hour off. `nil` only if the calendar cannot
    /// produce the match at all, which callers treat as "do not schedule".
    static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: boundaryHour, minute: 0, second: 0),
            matchingPolicy: .nextTime)
    }

    /// The canonical `YYYY-MM-DD` text form, which is also the persisted form.
    var displayText: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // Codable: persisted as the canonical text form so the saved record stays
    // readable. A malformed value decodes as a decoding error, which the
    // workspace record's lenient decode turns into "never reset" — the reset
    // then runs once, which is the safe direction (it only clears priorities,
    // which is what the next boundary would do anyway).
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.components(separatedBy: "-")
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "invalid workday: \(text)"))
        }
        self.year = year
        self.month = month
        self.day = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayText)
    }
}
