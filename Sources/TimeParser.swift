import Foundation

/// Reads a typed time — "6:15 india", "7:30am NY tomorrow", "tue 18:00 london", "9 cleveland",
/// "14.30 CET" — and returns the moment it means: on the day named, else on the day the grid shows.
@MainActor
enum TimeParser {
    /// Common abbreviations people write after a time.
    private static let abbreviations: [String: String] = [
        "ist": "Asia/Kolkata", "india": "Asia/Kolkata",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York", "eastern": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago", "central": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver", "mountain": "America/Denver",
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "gmt": "Europe/London", "bst": "Europe/London", "uk": "Europe/London",
        "cet": "Europe/Paris", "cest": "Europe/Paris",
        "sgt": "Asia/Singapore", "hkt": "Asia/Hong_Kong", "jst": "Asia/Tokyo", "kst": "Asia/Seoul",
        "gst": "Asia/Dubai", "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
        "utc": "UTC", "z": "UTC",
    ]

    private enum Day { case today, tomorrow, weekday(Int) }

    /// today / tonight, tomorrow (tmrw), and day names or their short forms (Calendar weekday 1 = Sunday).
    private static func day(_ w: String) -> Day? {
        switch w {
        case "today", "tonight": return .today
        case "tomorrow", "tmrw", "tmr", "tomorow", "tommorow": return .tomorrow
        default: break
        }
        let names = [["sun", "sunday"], ["mon", "monday"], ["tue", "tues", "tuesday"], ["wed", "weds", "wednesday"],
                     ["thu", "thur", "thurs", "thursday"], ["fri", "friday"], ["sat", "saturday"]]
        return names.firstIndex { $0.contains(w) }.map { .weekday($0 + 1) }
    }

    static func parse(_ text: String, store: Store) -> Date? {
        // Pull the day out first, wherever it is ("tue 7:30am NY", "7:30am NY on tuesday").
        var named: Day?, next = false
        let words = text.lowercased().split(separator: " ").map(String.init).filter { w in
            let bare = w.trimmingCharacters(in: .punctuationCharacters)
            if bare == "next" { next = true; return false }
            if bare == "on" { return false }
            if let d = day(bare) { named = d; return false }
            return true
        }
        let t = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let pattern = #"^(\d{1,2})(?:[:.h](\d{2})|(\d{2}))?\s*(?:(am|pm|a\.m\.|p\.m\.|a|p)(?![a-z]))?(?:\s+|(?=[^\d\s])|$)(.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: t).map { String(t[$0]) } }
        guard var hour = group(1).flatMap(Int.init) else { return nil }
        let minute = (group(2) ?? group(3)).flatMap(Int.init) ?? 0
        let meridiem = group(4)?.first
        guard minute < 60 else { return nil }
        if let mer = meridiem {
            guard (1...12).contains(hour) else { return nil }
            if mer == "p" && hour < 12 { hour += 12 }
            if mer == "a" && hour == 12 { hour = 0 }
        } else {
            guard hour < 24 else { return nil }
            // No am/pm: 1–6 reads as the afternoon (a 6:15 call is rarely at dawn), 7–11 as the morning.
            if (1...6).contains(hour) { hour += 12 }
        }
        guard let tz = zone(for: group(5) ?? "", store: store) else { return nil }
        if let named { return moment(hour: hour, minute: minute, in: tz, on: named, next: next, store: store) }
        return moment(hour: hour, minute: minute, in: tz, store: store)
    }

    /// The place after the time: one of his places, then a city, country, short code or
    /// abbreviation. Nothing means home.
    static func zone(for raw: String, store: Store) -> TimeZone? {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for word in ["in ", "for ", "at "] where q.hasPrefix(word) { q.removeFirst(word.count) }
        for word in [" time", " local"] where q.hasSuffix(word) { q.removeLast(word.count) }
        q = q.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return store.homeRow.tz }
        if let row = store.places.first(where: { $0.short.lowercased() == q || $0.label.lowercased().hasPrefix(q) }) { return row.tz }
        if let id = abbreviations[q] { return TimeZone(identifier: id) }
        if let city = Cities.curated.first(where: { $0.short.lowercased() == q }) { return TimeZone(identifier: city.zone) }
        if let city = Cities.search(q).first { return TimeZone(identifier: city.zone) }
        return nil
    }

    /// That wall-clock time on a named day in that place: today, tomorrow, or the next such
    /// weekday (today counts, unless he said "next").
    private static func moment(hour: Int, minute: Int, in tz: TimeZone, on d: Day, next: Bool, store: Store) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: store.now)
        var ahead = 0
        switch d {
        case .today: ahead = 0
        case .tomorrow: ahead = 1
        case .weekday(let w):
            ahead = (w - cal.component(.weekday, from: today) + 7) % 7
            if next && ahead == 0 { ahead = 7 }
        }
        guard let day = cal.date(byAdding: .day, value: ahead, to: today) else { return nil }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// That wall-clock time in that zone, on the 24 hours the grid shows — or, with now kept in the
    /// middle (half the grid is the past), the next time it comes round.
    private static func moment(hour: Int, minute: Int, in tz: TimeZone, store: Store) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        if store.config.rolling && store.dayOffset == 0 {
            let today = cal.startOfDay(for: store.now)
            return (0...2).lazy.compactMap { cal.date(byAdding: .day, value: $0, to: today) }
                .compactMap { cal.date(bySettingHour: hour, minute: minute, second: 0, of: $0) }
                .first { $0 > store.now }
        }
        let start = store.dayStart, end = start.addingTimeInterval(24 * 3600)
        let base = cal.startOfDay(for: start)
        for d in -1...1 {
            guard let day = cal.date(byAdding: .day, value: d, to: base),
                  let t = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if t >= start && t < end { return t }
        }
        return nil
    }
}
