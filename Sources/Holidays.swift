import Foundation

/// A public holiday in one country. `regional` names where it applies when it is not
/// nationwide ("England, Wales, Northern Ireland"); such days are shown but don't count as off.
struct Holiday: Codable, Equatable {
    let name: String
    var regional: String? = nil
}

/// Why a place isn't working on a day.
enum DayOff: Equatable {
    case weekend(String)            // "Saturday"
    case holiday(String)            // "Thanksgiving Day"
    case ownDay                     // a day off he added for this place
    case regional(String, String)   // "Easter Monday", "England, Wales, Northern Ireland"

    /// A proper day off (the regional ones only might be).
    var off: Bool { if case .regional = self { return false }; return true }

    var name: String {
        switch self {
        case .weekend(let d): return d
        case .holiday(let n): return n
        case .ownDay: return "Day off"
        case .regional(let n, _): return n
        }
    }
}

/// Countries: from a time zone (macOS's zone.tab), their names, and their usual working week.
enum Country {
    private static let byZone: [String: String] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t")
            if f.count >= 3 { out[String(f[2])] = String(f[0]) }
        }
        return out
    }()

    /// Older names the Mac may still report.
    private static let aliases = ["Asia/Calcutta": "Asia/Kolkata", "Asia/Saigon": "Asia/Ho_Chi_Minh", "Asia/Katmandu": "Asia/Kathmandu",
                                  "Asia/Rangoon": "Asia/Yangon", "Europe/Kiev": "Europe/Kyiv", "US/Eastern": "America/New_York",
                                  "US/Pacific": "America/Los_Angeles", "US/Central": "America/Chicago"]

    static func code(forZone zone: String) -> String? { byZone[zone] ?? aliases[zone].flatMap { byZone[$0] } }

    static func name(_ code: String) -> String {
        Locale(identifier: "en_GB").localizedString(forRegionCode: code) ?? code
    }

    /// Working days (Calendar weekday: 1 = Sunday) where the week isn't Monday to Friday.
    static func workingDays(_ code: String?) -> [Int] {
        switch code {
        case "SA", "QA", "KW", "BH", "OM", "EG", "JO", "IL", "IQ", "DZ", "LY", "SY", "SD", "YE": return [1, 2, 3, 4, 5]
        case "IR": return [7, 1, 2, 3, 4]
        default: return [2, 3, 4, 5, 6]
        }
    }
}

/// National public holidays, from Google Calendar's public holiday calendars (no account or key;
/// the request names only the country). Cached in Application Support/Halfpast/Holidays and
/// refreshed monthly; with no network the cache, or nothing, is used.
@MainActor
final class Holidays: ObservableObject {
    static let shared = Holidays()
    @Published private(set) var days: [String: [String: Holiday]] = [:]   // country → yyyy-MM-dd → holiday
    @Published private(set) var missing: Set<String> = []                // countries with no calendar
    private var asked: Set<String> = []

    private static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Halfpast/Holidays")

    private struct Cache: Codable { let fetched: Date; let days: [String: Holiday] }

    /// Google's calendar names: most countries go by their code (en.ae), the older ones by a word.
    private static let names = [
        "IN": "indian", "US": "usa", "GB": "uk", "FR": "french", "DE": "german", "SG": "singapore", "JP": "japanese",
        "AU": "australian", "CA": "canadian", "HK": "hong_kong", "CN": "china", "NL": "dutch", "IT": "italian",
        "ES": "spain", "IE": "irish", "BR": "brazilian", "MX": "mexican", "NZ": "new_zealand", "KR": "south_korea",
        "MY": "malaysia", "ID": "indonesian", "PH": "philippines", "SE": "swedish", "DK": "danish", "NO": "norwegian",
        "FI": "finnish", "PL": "polish", "PT": "portuguese", "RU": "russian", "TW": "taiwan", "VN": "vietnamese",
        "AT": "austrian", "GR": "greek", "ZA": "sa", "SA": "saudiarabian", "TR": "turkish", "UA": "ukrainian",
        "HU": "hungarian", "CZ": "czech", "RO": "romanian", "LT": "lithuanian",
    ]

    static func key(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func holiday(_ country: String, on day: String) -> Holiday? { days[country]?[day] }

    /// The next few holidays from a day, for the settings.
    func upcoming(_ country: String, from day: String, count: Int = 3) -> [(String, Holiday)] {
        (days[country] ?? [:]).filter { $0.key >= day && $0.value.regional == nil }.sorted { $0.key < $1.key }.prefix(count).map { ($0.key, $0.value) }
    }

    /// Loads a country's holidays from the cache, and fetches them if there are none or they are
    /// a month old.
    func ensure(_ country: String) {
        guard !asked.contains(country) else { return }
        asked.insert(country)
        let file = Holidays.dir.appendingPathComponent("\(country).json")
        let cache = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        if let cache { days[country] = cache.days }
        if snapshotMode { return }
        guard cache.map({ Date().timeIntervalSince($0.fetched) > 30 * 86400 }) ?? true else { return }
        Task {
            if let fetched = await Holidays.fetch(country) {
                days[country] = fetched
                missing.remove(country)
                try? FileManager.default.createDirectory(at: Holidays.dir, withIntermediateDirectories: true)
                try? JSONEncoder().encode(Cache(fetched: Date(), days: fetched)).write(to: file)
            } else if cache == nil {
                missing.insert(country)
            }
        }
    }

    private static func fetch(_ country: String) async -> [String: Holiday]? {
        var ids = [country.lowercased()]
        if let n = names[country] { ids.insert(n, at: 0) }
        for id in ids {
            guard let url = URL(string: "https://calendar.google.com/calendar/ical/en.\(id)%23holiday%40group.v.calendar.google.com/public/basic.ics"),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else { continue }
            return parse(text)
        }
        return nil
    }

    /// The public holidays in an .ics file: "Public holiday" ones count, "Public holiday in …"
    /// ones are regional, observances are left out.
    static func parse(_ ics: String) -> [String: Holiday] {
        let text = ics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "")
        var out: [String: Holiday] = [:]
        for event in text.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            var start: String?, end: String?, summary: String?, kind = ""
            for line in event.split(separator: "\n") {
                if line.hasPrefix("DTSTART") { start = line.split(separator: ":").last.map(String.init) }
                else if line.hasPrefix("DTEND") { end = line.split(separator: ":").last.map(String.init) }
                else if line.hasPrefix("SUMMARY:") { summary = unescape(String(line.dropFirst(8))) }
                else if line.hasPrefix("DESCRIPTION:") { kind = unescape(String(line.dropFirst(12))).components(separatedBy: "\n").first ?? "" }
            }
            guard let s = start, var name = summary, kind.hasPrefix("Public holiday") else { continue }
            name = name.replacingOccurrences(of: " (regional holiday)", with: "")
            let region = kind.hasPrefix("Public holiday in ") ? String(kind.dropFirst(18)) : nil
            for day in dates(from: s, to: end) {
                // Two on one day: a nationwide one wins; otherwise keep both names.
                if let had = out[day] {
                    if had.regional != nil && region == nil { out[day] = Holiday(name: name) }
                    else if (had.regional == nil) == (region == nil) && !had.name.contains(name) { out[day] = Holiday(name: had.name + " · " + name, regional: had.regional) }
                } else {
                    out[day] = Holiday(name: name, regional: region)
                }
            }
        }
        return out
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").trimmingCharacters(in: .whitespaces)
    }

    /// yyyymmdd start (and the day after the end) → each yyyy-MM-dd.
    private static func dates(from s: String, to e: String?) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func parse(_ x: String) -> Date? {
            let d = x.prefix(8)
            guard d.count == 8, let y = Int(d.prefix(4)), let m = Int(d.dropFirst(4).prefix(2)), let dd = Int(d.suffix(2)) else { return nil }
            return cal.date(from: DateComponents(year: y, month: m, day: dd))
        }
        guard let a = parse(s) else { return [] }
        let b = e.flatMap(parse) ?? a.addingTimeInterval(86400)
        var out: [String] = [], d = a
        while d < b && out.count < 14 { out.append(key(d, cal)); d = d.addingTimeInterval(86400) }
        return out.isEmpty ? [key(a, cal)] : out
    }
}
