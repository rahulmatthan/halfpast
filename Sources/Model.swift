import Foundation
import Combine

/// One place as written in places.json.
struct Place: Codable {
    var label: String
    var short: String
    var zone: String            // IANA name; "" follows the Mac's own time zone
    var home: Bool? = nil
    var abbr: String? = nil     // overrides tzdata's abbreviation (it calls Singapore "+08")
}

struct Config: Codable {
    var hourFormat = "24h"                      // 24h, 12h or utc
    var homeZones = ["Asia/Kolkata"]            // where the place that follows the Mac keeps its own label
    var favourites = ["Bangalore", "Cleveland"] // the two beside the notch; the home place is always one
    var clickSound = true                       // a soft click when the notch opens
    var appearance = "system"                   // system, light or dark
    var meetingMinutes = 60                     // the length of a proposed meeting: 15, 30, 45 or 60
    var places = Config.defaultPlaces

    static let defaultPlaces = [
        Place(label: "Bangalore", short: "BLR", zone: "", home: true),
        Place(label: "Singapore", short: "SIN", zone: "Asia/Singapore", abbr: "SGT"),
        Place(label: "London", short: "LON", zone: "Europe/London"),
        Place(label: "Paris", short: "PAR", zone: "Europe/Paris"),
        Place(label: "Cleveland", short: "CLE", zone: "America/New_York"),
        Place(label: "San Francisco", short: "SF", zone: "America/Los_Angeles"),
    ]

    init() {}

    // Every key is optional, so an older places.json keeps working when a setting is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        hourFormat = try c.decodeIfPresent(String.self, forKey: .hourFormat) ?? d.hourFormat
        homeZones = try c.decodeIfPresent([String].self, forKey: .homeZones) ?? d.homeZones
        favourites = try c.decodeIfPresent([String].self, forKey: .favourites)
            ?? decoder.container(keyedBy: Legacy.self).decodeIfPresent([String].self, forKey: .notch)   // before 19 Oct 2026
            ?? d.favourites
        clickSound = try c.decodeIfPresent(Bool.self, forKey: .clickSound) ?? d.clickSound
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? d.appearance
        meetingMinutes = try c.decodeIfPresent(Int.self, forKey: .meetingMinutes) ?? d.meetingMinutes
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? d.places
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/zones/places.json")

    /// Reads places.json. Writes it on first run, and rewrites it when a newer setting is
    /// missing so the file always shows every option.
    static func load() -> Config {
        let data = try? Data(contentsOf: url)
        if let data, (try? JSONDecoder().decode(Config.self, from: data)) == nil { return Config() }  // broken file: leave it for him to fix
        let read = data.flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        let c = read.tidied()
        let keys = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?.keys
        if keys.map({ Set($0) != Set(CodingKeys.allNames) }) ?? true || c.favourites != read.favourites || c.places.map(\.label) != read.places.map(\.label) {
            c.save()
        }
        return c
    }

    static func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    var homeIndex: Int { places.firstIndex { $0.home == true } ?? 0 }

    /// Keeps the rules true whatever the file says: exactly one home, first in the list, and
    /// among the (at most two) favourites, which name places that exist.
    func tidied() -> Config {
        var c = self
        guard !c.places.isEmpty else { return Config() }
        let h = c.homeIndex
        for i in c.places.indices { c.places[i].home = i == h ? true : nil }
        c.places.insert(c.places.remove(at: h), at: 0)
        let home = c.places[0].label
        var favs = [home]
        for f in c.favourites where !Config.same(f, home) && c.places.contains(where: { Config.same($0.label, f) }) { favs.append(f) }
        c.favourites = Array(favs.prefix(2))
        return c
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(self).write(to: Config.url)
    }

    enum CodingKeys: String, CodingKey {
        case hourFormat, homeZones, favourites, clickSound, appearance, meetingMinutes, places
        static let allNames = ["hourFormat", "homeZones", "favourites", "clickSound", "appearance", "meetingMinutes", "places"]
    }
    private enum Legacy: String, CodingKey { case notch }
}

/// Where a place is in its day — drives the marks beside the notch and the cell colours.
enum Phase {
    case work, awake, asleep
    init(hour: Int) { self = hour >= 8 && hour < 18 ? .work : hour >= 6 && hour < 23 ? .awake : .asleep }
}

/// A row of the grid, resolved to a real time zone.
struct Row: Identifiable {
    let id: Int
    let label: String
    let short: String
    let tz: TimeZone
    let abbrOverride: String?
    let isHome: Bool
    let cal: Calendar

    init(id: Int, label: String, short: String, tz: TimeZone, abbr: String?, isHome: Bool) {
        self.id = id; self.label = label; self.short = short; self.tz = tz
        self.abbrOverride = abbr; self.isHome = isHome
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        cal = c
    }

    static let utcID = 1000

    func abbr(at date: Date) -> String {
        if let a = abbrOverride, !a.isEmpty { return a }
        return tzAbbreviation(tz.identifier, date) ?? tz.abbreviation(for: date) ?? ""
    }

    func offsetMinutes(at date: Date) -> Int { tz.secondsFromGMT(for: date) / 60 }

    func hours(at date: Date) -> Double {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    func phase(at date: Date) -> Phase { Phase(hour: cal.component(.hour, from: date)) }
}

/// tzdata's own abbreviation (IST, BST, CEST, EDT) — Foundation gives "GMT+5:30" instead.
/// Numeric ones ("+08") come back nil.
func tzAbbreviation(_ id: String, _ date: Date) -> String? {
    if id == "GMT" || id == "UTC" { return "UTC" }
    let old = getenv("TZ").map { String(cString: $0) }
    setenv("TZ", id, 1); tzset()
    var t = time_t(date.timeIntervalSince1970)
    var parts = tm()
    localtime_r(&t, &parts)
    let s = parts.tm_zone.map { String(cString: $0) } ?? ""
    if let old { setenv("TZ", old, 1) } else { unsetenv("TZ") }
    tzset()
    return s.isEmpty || s.hasPrefix("+") || s.hasPrefix("-") ? nil : s
}

enum HourFormat: String, CaseIterable {
    case h24 = "24h", h12 = "12h", utc = "utc"
    var next: HourFormat { let all = HourFormat.allCases; return all[(all.firstIndex(of: self)! + 1) % all.count] }
    var twelve: Bool { self == .h12 }
}

@MainActor
final class Store: ObservableObject {
    @Published var now = Date()
    @Published var hoverCol: Int?
    @Published var proposal: Date?      // the start of the meeting he is proposing (duration long)
    @Published var hidden: Set<String> = []   // places left out for now (lower-cased labels); not saved
    @Published var dayOffset = 0        // days after home's today that the grid shows
    static let durations = [15, 30, 45, 60]
    @Published var timeQuery: String?   // what he is typing into the time field; nil when not typing
    private var beforeTyping: (Date?, Int) = (nil, 0)
    @Published var format: HourFormat = .h24
    @Published var flash: String?
    @Published private(set) var config = Config.load()

    private var timer: Timer?

    init() {
        format = HourFormat(rawValue: config.hourFormat.lowercased()) ?? .h24
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            NSTimeZone.resetSystemTimeZone()
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        config = Config.load()
        now = Date()
    }

    var selectedCol: Int? { hoverCol ?? proposal.map(col) }

    func isHidden(_ row: Row) -> Bool { hidden.contains(row.label.lowercased()) }

    func toggleHidden(_ row: Row) {
        let key = row.label.lowercased()
        if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
    }

    /// The places in play: everything not hidden (all of them if he has hidden every one).
    var visiblePlaces: [Row] {
        let v = places.filter { !isHidden($0) }
        return v.isEmpty ? places : v
    }

    func col(_ date: Date) -> Int { max(0, min(23, Int(floor(date.timeIntervalSince(dayStart) / 3600)))) }

    /// The configured places, without the UTC reference row.
    var places: [Row] {
        config.places.enumerated().map { i, p in
            let home = p.home == true
            let tz = p.zone.isEmpty ? TimeZone.current : (TimeZone(identifier: p.zone) ?? TimeZone.current)
            var label = p.label, short = p.short
            // Travelling: the place that follows the Mac says where its clock actually is.
            if p.zone.isEmpty && !config.homeZones.isEmpty && !config.homeZones.contains(tz.identifier) {
                label = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? label
                short = String(label.prefix(3)).uppercased()
            }
            return Row(id: i, label: label, short: short, tz: tz, abbr: p.abbr, isHome: home)
        }
    }

    var rows: [Row] {
        var out = places
        if format == .utc {
            let at = (out.firstIndex { $0.isHome }).map { $0 + 1 } ?? 0
            out.insert(Row(id: Row.utcID, label: "UTC", short: "UTC", tz: TimeZone(identifier: "UTC")!, abbr: "", isHome: false), at: at)
        }
        return out
    }

    /// Beside the notch: home on the left, the other favourite on the right (the next place
    /// in the list if there is no second favourite).
    var notchRows: [Row] {
        let all = places
        var picked = [homeRow]
        if let f = config.favourites.first(where: { !Config.same($0, config.places[config.homeIndex].label) }),
           let i = config.places.firstIndex(where: { Config.same($0.label, f) }) { picked.append(all[i]) }
        for r in all where picked.count < 2 && !picked.contains(where: { $0.id == r.id }) { picked.append(r) }
        return picked
    }

    // MARK: changing the places (from the settings view; every change is saved straight away)

    /// Six rows: the most the ribbon shows without crowding a 14-inch screen.
    static let maxPlaces = 6

    private func change(_ edit: (inout Config) -> Void) {
        var c = config
        edit(&c)
        c = c.tidied()
        c.save()
        config = c
    }

    func isHome(_ i: Int) -> Bool { config.places[i].home == true }

    func isFavourite(_ i: Int) -> Bool { config.favourites.contains { Config.same($0, config.places[i].label) } }

    /// Stars a place. Home is always one of the two favourites, so starring another replaces
    /// the second; the home place can't be unstarred.
    func toggleFavourite(_ i: Int) {
        guard !isHome(i) else { return }
        let label = config.places[i].label
        change { c in
            if c.favourites.contains(where: { Config.same($0, label) }) {
                c.favourites.removeAll { Config.same($0, label) }
            } else {
                c.favourites = [c.places[c.homeIndex].label, label]
            }
        }
    }

    /// Makes a favourite the home: it moves to the top and everything is measured from it.
    func setHome(_ i: Int) {
        guard !isHome(i) else { return }
        let old = config.places[config.homeIndex].label
        change { c in
            for j in c.places.indices { c.places[j].home = j == i ? true : nil }
            c.favourites = [c.places[i].label, old]
        }
    }

    func rename(_ i: Int, to label: String) {
        let old = config.places[i].label
        change { c in
            c.places[i].label = label
            c.favourites = c.favourites.map { Config.same($0, old) ? label : $0 }
        }
    }

    func remove(_ i: Int) {
        guard !isHome(i) else { return }
        change { $0.places.remove(at: i) }   // tidied() drops it from the favourites
    }

    func add(_ city: City) {
        guard config.places.count < Store.maxPlaces else { return }
        change { $0.places.append(Place(label: city.name, short: city.short, zone: city.zone)) }
    }

    /// Moves a place up or down; the home place stays first.
    func move(_ i: Int, by d: Int) {
        let j = i + d
        guard j >= 0, j < config.places.count, !isHome(i), !isHome(j) else { return }
        change { $0.places.swapAt(i, j) }
    }

    func setAppearance(_ a: String) { change { $0.appearance = a } }

    func has(_ city: City) -> Bool {
        config.places.contains { $0.zone == city.zone && $0.label.caseInsensitiveCompare(city.name) == .orderedSame }
    }

    var homeRow: Row { places.first { $0.isHome } ?? places[0] }

    /// Column 0 of the grid: the home zone's most recent midnight.
    var dayStart: Date {
        let today = homeRow.cal.startOfDay(for: now)
        return homeRow.cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
    }

    /// Shows another day; a proposed time moves with it, keeping its time of day.
    func changeDay(by d: Int) {
        let old = dayStart
        dayOffset += d
        if let p = proposal { proposal = dayStart.addingTimeInterval(p.timeIntervalSince(old)) }
        hoverCol = nil
    }

    /// Proposes a moment on whatever day it falls (home's date), moving the grid there.
    func show(_ t: Date) {
        let cal = homeRow.cal
        dayOffset = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: t)).day ?? 0
        proposal = t
        hoverCol = nil
    }

    var duration: Int { Store.durations.contains(config.meetingMinutes) ? config.meetingMinutes : 60 }

    func setDuration(_ m: Int) {
        change { $0.meetingMinutes = m }
        if let p = proposal { place(p) }   // keep the shorter or longer block on the grid
    }

    func cycleDuration() {
        let i = Store.durations.firstIndex(of: duration) ?? 3
        setDuration(Store.durations[(i + 1) % Store.durations.count])
    }

    func instant(_ col: Int) -> Date { dayStart.addingTimeInterval(Double(col) * 3600) }

    /// The moment the headers describe: the hovered hour, else the proposed time, else now.
    var focus: Date { proposal ?? hoverCol.map(instant) ?? now }

    /// The home hour that is least unkind to the worst-off place: hours outside 8–18 count
    /// against a place, the smallest worst case wins, and the total breaks ties.
    var fairestCol: Int {
        func penalty(_ t: Double) -> Double {
            t >= 8 && t <= 18 ? 0 : min((8 - t + 24).truncatingRemainder(dividingBy: 24), (t - 18 + 24).truncatingRemainder(dividingBy: 24))
        }
        let ps = visiblePlaces
        var best = (Double.infinity, Double.infinity), col = 0
        for c in 0..<24 {
            let p = ps.map { penalty($0.hours(at: instant(c))) }
            let score = (p.max() ?? 0, p.reduce(0, +))
            if score.0 < best.0 || (score.0 == best.0 && score.1 < best.1) { best = score; col = c }
        }
        return col
    }

    /// Slides the proposed block by minutes (snapped to 5), starting from the current hour,
    /// and keeps the whole hour on the grid.
    func step(minutes: Int) {
        let base = proposal ?? instant(col(now))
        place(base.addingTimeInterval(Double(minutes) * 60))
    }

    /// Puts the block at a moment, snapped to 5 minutes and kept within the day shown.
    func place(_ t: Date) {
        let fromStart = (t.timeIntervalSince(dayStart) / 300).rounded() * 300
        let latest = Double(24 * 60 - duration) * 60
        proposal = dayStart.addingTimeInterval(min(max(fromStart, 0), latest))
        hoverCol = nil
    }

    func propose(col: Int) { proposal = instant(col); hoverCol = nil }

    func jumpToFairest() { propose(col: fairestCol) }

    func backToNow() { proposal = nil; hoverCol = nil; timeQuery = nil; dayOffset = 0 }

    var proposalIsFairest: Bool { proposal == instant(fairestCol) }

    // MARK: typing a time ("6:15 india", "7:30am NY")

    func startTyping(_ first: String = "") {
        beforeTyping = (proposal, dayOffset)
        timeQuery = first
        preview()
    }

    /// Moves the proposal as he types; text that doesn't read as a time leaves it where it was.
    func preview() {
        guard let q = timeQuery else { return }
        if let t = TimeParser.parse(q, store: self) { show(t) } else if q.isEmpty { (proposal, dayOffset) = beforeTyping }
    }

    /// Return keeps what the text says; esc puts back the time from before.
    func finishTyping(keep: Bool) {
        if !keep { (proposal, dayOffset) = beforeTyping }
        timeQuery = nil
    }

    var timeQueryValid: Bool { timeQuery.map { TimeParser.parse($0, store: self) != nil } ?? false }

    // MARK: formatting

    func time(_ date: Date, _ row: Row) -> String {
        let c = row.cal.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        if format.twelve { return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m)) \(h < 12 ? "AM" : "PM")" }
        return String(format: "%02d:%02d", h, m)
    }

    func date(_ date: Date, _ row: Row) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = row.tz
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    func diff(_ row: Row, at date: Date) -> String {
        let d = row.offsetMinutes(at: date) - homeRow.offsetMinutes(at: date)
        if d == 0 { return "" }
        let a = abs(d)
        return (d < 0 ? "−" : "+") + (a % 60 == 0 ? "\(a / 60)h" : "\(a / 60):\(String(format: "%02d", a % 60))")
    }

    func hourLabel(_ hour: Int) -> String {
        format.twelve ? "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")" : "\(hour)"
    }

    /// "Bangalore 18:15  ·  Singapore 20:45  ·  …" for the bottom bar.
    func summary(at moment: Date) -> String {
        visiblePlaces.map { "\($0.label) \(time(moment, $0))" }.joined(separator: "  ·  ")
    }

    /// Plain text of every place at a moment, for pasting into a message or an invite.
    func asText(at moment: Date) -> String {
        visiblePlaces.map { "\($0.label) \(time(moment, $0)) \(date(moment, $0)) (\($0.abbr(at: moment)))" }.joined(separator: "\n")
    }

    /// "06:10–07:10" in a place's own time.
    func range(from start: Date, _ row: Row) -> String {
        "\(time(start, row))–\(time(start.addingTimeInterval(Double(duration) * 60), row))"
    }

    /// The meeting for an email: each place's start–end, abbreviation and date.
    func emailText(from start: Date) -> String {
        let end = start.addingTimeInterval(Double(duration) * 60)
        let lines = visiblePlaces.map { r in
            "\(r.label): \(time(start, r))–\(time(end, r)) \(r.abbr(at: start)), \(date(start, r))"
        }
        return "Proposed time (\(duration == 60 ? "1 hour" : "\(duration) minutes")):\n" + lines.joined(separator: "\n")
    }
}
