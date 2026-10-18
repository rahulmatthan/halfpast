import Foundation
import Combine

/// One place as written in places.json.
struct Place: Codable {
    var label: String
    var short: String
    var zone: String            // IANA name; "" follows the Mac's own time zone
    var home: Bool? = nil
    var abbr: String? = nil     // overrides tzdata's abbreviation (it calls Singapore "+08")
    var work: [Double]? = nil   // working hours [start, end] in its own time; 8–18 when absent
    var workdays: [Int]? = nil  // working days (1 = Sunday); the country's usual week when absent
    var holidays: Bool? = nil   // false leaves out its public holidays
    var daysOff: [String]? = nil    // its own days off, yyyy-MM-dd
}

/// Away from home: the Mac's clock is on another zone. `here` is his answer to "plan from here?".
struct Travel: Codable, Equatable {
    var zone: String
    var here: Bool
}

struct Config: Codable {
    var hourFormat = "24h"                      // 24h, 12h or utc
    var homeZones = [TimeZone.current.identifier]   // where the place that follows the Mac keeps its own label
    var favourites = Config.defaultFavourites       // the two beside the notch; the home place is always one
    var clickSound = true                       // a soft click when the notch opens
    var appearance = "system"                   // system, light or dark
    var meetingMinutes = 60                     // the length of a proposed meeting: 15, 30, 45 or 60
    var welcomed = false                        // the first-run welcome has been shown
    var travel: Travel? = nil                   // set while the Mac is on another zone
    var places = Config.defaultPlaces

    /// A new Mac's places: home (its own time zone, named after its city) and the first three of
    /// London, New York, Singapore and Tokyo that are somewhere else.
    static var defaultPlaces: [Place] {
        let here = TimeZone.current.identifier
        let name = Cities.curated.first { $0.zone == here }?.name
            ?? here.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Home"
        let home = Place(label: name, short: shortLabel(name), zone: "", home: true)
        let others = [("London", "LON", "Europe/London"), ("New York", "NYC", "America/New_York"),
                      ("Singapore", "SIN", "Asia/Singapore"), ("Tokyo", "TYO", "Asia/Tokyo")]
            .filter { $0.2 != here && $0.0 != name }
            .prefix(3)
            .map { Place(label: $0.0, short: $0.1, zone: $0.2) }
        return [home] + others
    }

    static var defaultFavourites: [String] { Array(defaultPlaces.prefix(2).map(\.label)) }

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
        welcomed = try c.decodeIfPresent(Bool.self, forKey: .welcomed) ?? d.welcomed
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? d.places
        travel = try c.decodeIfPresent(Travel.self, forKey: .travel)
    }

    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Halfpast/places.json")

    /// Before the name Halfpast the file lived at ~/.config/zones/places.json; carry it over once.
    private static func adoptOldFile() {
        let old = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/zones/places.json")
        guard !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: old.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: old, to: url)
    }

    /// Reads places.json. Writes it on first run, and rewrites it when a newer setting is
    /// missing so the file always shows every option.
    @MainActor static func load() -> Config {
        adoptOldFile()
        let data = try? Data(contentsOf: url)
        if let data, (try? JSONDecoder().decode(Config.self, from: data)) == nil { return Config() }  // broken file: leave it for him to fix
        let read = data.flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        let c = read.tidied()
        let keys = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?.keys
        if keys.map({ !Set(CodingKeys.allNames).isSubset(of: Set($0)) }) ?? true || c.favourites != read.favourites || c.places.map(\.label) != read.places.map(\.label) {
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

    @MainActor func save() {
        if snapshotMode { return }      // screenshots never touch his settings
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(self).write(to: Config.url)
    }

    enum CodingKeys: String, CodingKey {
        case hourFormat, homeZones, favourites, clickSound, appearance, meetingMinutes, welcomed, travel, places
        static let allNames = ["hourFormat", "homeZones", "favourites", "clickSound", "appearance", "meetingMinutes", "welcomed", "places"]
    }
    private enum Legacy: String, CodingKey { case notch }
}

/// Where a place is in its day — drives the marks beside the notch and the cell colours.
enum Phase {
    case work, awake, asleep, off   // off: its working hours, on a weekend or holiday
}

/// A row of the grid, resolved to a real time zone.
struct Row: Identifiable {
    let id: Int
    let label: String
    let short: String
    let tz: TimeZone
    let abbrOverride: String?
    var isHome: Bool
    let cal: Calendar
    var work: (start: Double, end: Double) = (8, 18)
    var workdays: Set<Int> = [2, 3, 4, 5, 6]
    var country: String?            // for its public holidays; nil when they are switched off
    var daysOff: Set<String> = []

    init(id: Int, label: String, short: String, tz: TimeZone, abbr: String?, isHome: Bool) {
        self.id = id; self.label = label; self.short = short; self.tz = tz
        self.abbrOverride = abbr; self.isHome = isHome
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        cal = c
        country = Country.code(forZone: tz.identifier)
        workdays = Set(Country.workingDays(country))
    }

    /// A place's own week: its hours, days, holidays and days off.
    init(id: Int, place p: Place, tz: TimeZone, isHome: Bool) {
        self.init(id: id, label: p.label, short: p.short, tz: tz, abbr: p.abbr, isHome: isHome)
        if let w = p.work, w.count == 2 { work = (w[0], w[1]) }
        if let d = p.workdays { workdays = Set(d) }
        if p.holidays == false { country = nil }
        daysOff = Set(p.daysOff ?? [])
    }

    static let utcID = 1000
    static let hereID = 2000

    /// Within its working hours (which may run past midnight), whatever the day.
    func inHours(_ h: Double) -> Bool {
        work.start < work.end ? h >= work.start && h < work.end : h >= work.start || h < work.end
    }

    /// "8–18" or "9:30–17:30" (always 24-hour: it is a setting, not a time).
    var hoursText: String {
        func f(_ h: Double) -> String { h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))" : "\(Int(h)):\(String(format: "%02d", Int((h.truncatingRemainder(dividingBy: 1) * 60).rounded())))" }
        return "\(f(work.start))–\(f(work.end))"
    }

    /// "Mon–Fri", "Sun–Thu", or the days listed.
    var daysText: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let order = [2, 3, 4, 5, 6, 7, 1]
        let on = order.filter(workdays.contains)
        if on.isEmpty { return "no working days" }
        if on.count == 7 { return "every day" }
        // A run through the week (wrapping round Sunday) reads as first–last.
        for s in 0..<7 {
            let run = (0..<on.count).map { order[(s + $0) % 7] }
            if Set(run) == Set(on) { return on.count == 1 ? names[run[0] - 1] : "\(names[run.first! - 1])–\(names[run.last! - 1])" }
        }
        return on.map { names[$0 - 1] }.joined(separator: " ")
    }

    func abbr(at date: Date) -> String {
        if let a = abbrOverride, !a.isEmpty { return a }
        return tzAbbreviation(tz.identifier, date) ?? tz.abbreviation(for: date) ?? ""
    }

    func offsetMinutes(at date: Date) -> Int { tz.secondsFromGMT(for: date) / 60 }

    func hours(at date: Date) -> Double {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

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
    private var holidayWatch: AnyCancellable?

    init() {
        format = HourFormat(rawValue: config.hourFormat.lowercased()) ?? .h24
        holidayWatch = Holidays.shared.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        fetchHolidays()
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
        // Home again: travel is over.
        if !away && config.travel != nil { change { $0.travel = nil } }
        fetchHolidays()
    }

    /// Loads (or fetches) the public holidays of every place's country.
    func fetchHolidays() {
        for r in planRows { if let c = r.country { Holidays.shared.ensure(c) } }
    }

    var selectedCol: Int? { hoverCol ?? proposal.map(col) }

    func isHidden(_ row: Row) -> Bool { hidden.contains(row.label.lowercased()) }

    func toggleHidden(_ row: Row) {
        let key = row.label.lowercased()
        if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
    }

    /// The places in play: everything not hidden (all of them if he has hidden every one).
    var visiblePlaces: [Row] {
        let all = planRows
        let v = all.filter { !isHidden($0) }
        return v.isEmpty ? all : v
    }

    func col(_ date: Date) -> Int { max(0, min(23, Int(floor(date.timeIntervalSince(dayStart) / 3600)))) }

    /// The configured places in their order (ids are their places.json index), without the UTC
    /// row or a travel row. A place that follows the Mac stays on home's zone while he travels.
    var places: [Row] {
        config.places.enumerated().map { i, p in
            let tz = p.zone.isEmpty ? (macElsewhere ? homeZone : TimeZone.current) : (TimeZone(identifier: p.zone) ?? TimeZone.current)
            return Row(id: i, place: p, tz: tz, isHome: p.home == true)
        }
    }

    // MARK: travel

    /// Home's own zone: the home place's, or for one that follows the Mac, the zone it was set up in.
    var homeZone: TimeZone {
        let p = config.places[config.homeIndex]
        if !p.zone.isEmpty, let tz = TimeZone(identifier: p.zone) { return tz }
        return config.homeZones.first.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// The Mac's clock is on a zone that isn't home's (home's places then keep home's zone).
    var macElsewhere: Bool {
        let mac = TimeZone.current.identifier
        return mac != homeZone.identifier && !config.homeZones.contains(mac)
    }

    /// Elsewhere on a different clock: worth asking whether to plan from there.
    var away: Bool { macElsewhere && TimeZone.current.secondsFromGMT() != homeZone.secondsFromGMT() }

    /// Away and asked to plan from here: the grid is measured from where the Mac is.
    var planningHere: Bool { away && config.travel == Travel(zone: TimeZone.current.identifier, here: true) }

    /// Away on a zone he hasn't been asked about yet.
    var travelUndecided: Bool { away && config.travel?.zone != TimeZone.current.identifier }

    /// The city the Mac's clock is on: one of his places, a known city, else the zone's own name.
    var hereName: String {
        let id = TimeZone.current.identifier
        if let p = config.places.first(where: { $0.zone == id }) { return p.label }
        return Cities.curated.first { $0.zone == id }?.name
            ?? id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
    }

    var homeName: String { config.places[config.homeIndex].label }

    func planFromHere(_ yes: Bool) {
        change { $0.travel = Travel(zone: TimeZone.current.identifier, here: yes) }
        backToNow()
        fetchHolidays()
    }

    /// The rows the ribbon is built from: the places, and while he plans from abroad, where he
    /// is first as the home row (one of his places if it is on that zone, else a row of its own).
    var planRows: [Row] {
        var out = places
        guard planningHere else { return out }
        let here = TimeZone.current
        for i in out.indices { out[i].isHome = false }
        if let i = out.firstIndex(where: { $0.tz.identifier == here.identifier }) {
            var r = out.remove(at: i)
            r.isHome = true
            return [r] + out
        }
        let name = hereName
        return [Row(id: Row.hereID, label: name, short: shortLabel(name), tz: here, abbr: nil, isHome: true)] + out
    }

    var rows: [Row] {
        var out = planRows
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
        var picked = [all[config.homeIndex]]
        if let f = config.favourites.first(where: { !Config.same($0, config.places[config.homeIndex].label) }),
           let i = config.places.firstIndex(where: { Config.same($0.label, f) }) { picked.append(all[i]) }
        for r in all where picked.count < 2 && !picked.contains(where: { $0.id == r.id }) { picked.append(r) }
        return picked
    }

    // MARK: changing the places (from the settings view; every change is saved straight away)

    /// Six rows: the most the ribbon shows without crowding a 14-inch screen.
    static let maxPlaces = 6

    func change(_ edit: (inout Config) -> Void) {
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

    func markWelcomed() { change { $0.welcomed = true } }

    /// Screenshots only: show a different set of places without touching his file.
    func showWithoutSaving(_ c: Config) { config = c.tidied() }

    func has(_ city: City) -> Bool {
        config.places.contains { $0.zone == city.zone && $0.label.caseInsensitiveCompare(city.name) == .orderedSame }
    }

    var homeRow: Row { planRows.first { $0.isHome } ?? planRows[0] }

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

    /// The home hour that is least unkind to the worst-off place: each hour outside a place's
    /// working hours counts against it, and a weekend or holiday there counts four more (a
    /// regional holiday one more); the smallest worst case wins, and the total breaks ties.
    var fairestCol: Int {
        func penalty(_ r: Row, _ at: Date) -> Double {
            let t = r.hours(at: at), s = r.work.start, e = r.work.end
            let outside = r.inHours(t) || t == e ? 0
                : min((s - t + 24).truncatingRemainder(dividingBy: 24), (t - e + 24).truncatingRemainder(dividingBy: 24))
            let day = dayOff(r, at: at)
            return outside + (day == nil ? 0 : day!.off ? 4 : 1)
        }
        let ps = visiblePlaces
        var best = (Double.infinity, Double.infinity), col = 0
        for c in 0..<24 {
            let p = ps.map { penalty($0, instant(c)) }
            let score = (p.max() ?? 0, p.reduce(0, +))
            if score.0 < best.0 || (score.0 == best.0 && score.1 < best.1) { best = score; col = c }
        }
        return col
    }

    // MARK: working weeks and holidays

    /// Why a place isn't working on the day a moment falls (in its own time), if it isn't.
    func dayOff(_ r: Row, at date: Date) -> DayOff? {
        let key = Holidays.key(date, r.cal)
        if r.daysOff.contains(key) { return .ownDay }
        if let c = r.country, let h = Holidays.shared.holiday(c, on: key) {
            if let region = h.regional {
                if r.workdays.contains(r.cal.component(.weekday, from: date)) { return .regional(h.name, region) }
            } else {
                return .holiday(h.name)
            }
        }
        let w = r.cal.component(.weekday, from: date)
        if !r.workdays.contains(w) { return .weekend(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][w - 1]) }
        return nil
    }

    /// Working, awake, asleep — or off: its working hours on a holiday or day off. A weekend's
    /// working hours just read as awake, so holidays stand out. `mid` reads a grid cell at its middle.
    func phase(_ r: Row, at date: Date, mid: Bool = false) -> Phase {
        let t = date.addingTimeInterval(mid ? 1800 : 0)
        let h = r.hours(at: t)
        if r.inHours(h) {
            switch dayOff(r, at: t) {
            case nil, .regional: return .work
            case .weekend: return .awake
            case .holiday, .ownDay: return .off
            }
        }
        let wake = min(6, r.work.start), sleep = max(23, r.work.end)
        return h >= wake && h < sleep ? .awake : .asleep
    }

    /// "Thanksgiving Day in Cleveland", "Saturday in Dubai", "maybe Easter Monday in London" —
    /// the places a moment would ask to give up a day off.
    func offNotes(at t: Date) -> [String] {
        var groups: [(String, [String])] = []     // "Sunday" → the places it is Sunday in
        for r in visiblePlaces {
            guard let d = dayOff(r, at: t) else { continue }
            let name: String
            if case .regional = d { name = "maybe \(d.name)" } else { name = d.name }
            if let i = groups.firstIndex(where: { $0.0 == name }) { groups[i].1.append(r.label) } else { groups.append((name, [r.label])) }
        }
        let all = visiblePlaces.count
        return groups.map { name, where_ in
            where_.count == all && all > 1 ? "\(name) everywhere" : "\(name) in " + where_.joined(separator: ", ")
        }
    }

    private func editPlace(_ i: Int, _ edit: @escaping (inout Place, Row) -> Void) {
        guard i < config.places.count else { return }
        let row = places[i]
        change { edit(&$0.places[i], row) }
        fetchHolidays()
    }

    /// Moves the start or end of a place's working day by half an hour.
    func nudgeWork(_ i: Int, start: Bool, by d: Double) {
        editPlace(i) { p, r in
            var w = [r.work.start, r.work.end]
            let k = start ? 0 : 1
            w[k] = min(max(w[k] + d, 0), 24)
            if w[0] != w[1] { p.work = w == [8, 18] ? nil : w }
        }
    }

    func toggleWorkday(_ i: Int, _ day: Int) {
        editPlace(i) { p, r in
            var d = r.workdays
            if d.contains(day) { d.remove(day) } else { d.insert(day) }
            p.workdays = d == Set(Country.workingDays(Country.code(forZone: r.tz.identifier))) ? nil : d.sorted()
        }
    }

    func setHolidays(_ i: Int, _ on: Bool) { editPlace(i) { p, _ in p.holidays = on ? nil : false } }

    func addDayOff(_ i: Int, _ key: String) {
        editPlace(i) { p, _ in p.daysOff = Array(Set((p.daysOff ?? []) + [key])).sorted() }
    }

    func removeDayOff(_ i: Int, _ key: String) {
        editPlace(i) { p, _ in p.daysOff = (p.daysOff ?? []).filter { $0 != key }; if p.daysOff?.isEmpty == true { p.daysOff = nil } }
    }

    /// Back to 8–18 on the country's usual week, with its holidays.
    func resetWeek(_ i: Int) { editPlace(i) { p, _ in p.work = nil; p.workdays = nil; p.holidays = nil } }

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
