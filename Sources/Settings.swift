import SwiftUI

/// Places & appearance, shown in the same glass panel in place of the ribbon: the places you
/// have (rename, reorder, pin two to the notch, remove), a search to add one while there is
/// room, and light / dark / match the Mac.
struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    @Environment(\.colorScheme) private var scheme
    @State private var query: String

    init(store: Store, ui: NotchUI, query: String = "", editing: Int? = nil) {
        self.store = store
        self.ui = ui
        _query = State(initialValue: query)
        _editing = State(initialValue: editing)
    }
    @State private var editing: Int?        // the place whose working week is open on the right
    @State private var newDayOff = Date()
    @State private var remote: [City] = []
    @State private var lookingUp = false
    @FocusState private var searching: Bool
    @State private var loginOn = LoginItem.enabled

    var body: some View {
        let p = Palette.of(scheme)
        PanelChrome {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text("Places & appearance").font(hanken(22, .semibold))
                    Spacer()
                    HStack(spacing: 8) {
                        Text("Keep now in the middle").font(hanken(12, .semibold)).foregroundStyle(p.mist)
                        toggle(store.config.rolling, p) { store.setRolling($0) }
                    }
                    .help("The ribbon shows twelve hours either side of now, and the rows drift as time passes")
                    .padding(.trailing, 6)
                    appearancePicker(p)
                    Button { ui.settingsShown = false } label: {
                        Text("Done").font(hanken(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(p.button, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your places  ·  \(store.config.places.count) of \(Store.maxPlaces)")
                            .font(hanken(13, .semibold)).foregroundStyle(p.mist)
                        ForEach(Array(store.config.places.indices), id: \.self) { i in placeRow(i, p) }
                    }
                    .frame(width: 560, alignment: .topLeading)

                    if let i = editing, i < store.config.places.count {
                        week(i, p).frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a place").font(hanken(13, .semibold)).foregroundStyle(p.mist)
                        if store.config.places.count >= Store.maxPlaces {
                            Text("Six places is the most the ribbon shows comfortably. Remove one with − to make room for another.")
                                .font(hanken(13)).foregroundStyle(p.mist)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(p.chip, in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            searchField(p)
                            results(p)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 12)
                HStack {
                    (Text(Image(systemName: "star.fill")).foregroundColor(p.fair) + Text("  Two favourites sit beside the notch.     ")
                    + Text(Image(systemName: "house.fill")).foregroundColor(p.homeTime) + Text("  One is home, the clock the rest follow."))
                    .font(hanken(12)).foregroundStyle(p.mist)
                    Spacer()
                    // Also on the right-click menu, which a menu bar manager like Ice can swallow.
                    HStack(spacing: 10) {
                        Text("Halfpast \(ui.version)").foregroundStyle(p.mist)
                        Button { ui.onUpdates() } label: {
                            Text(ui.updateReady.map { "Update to \($0)" } ?? "Check for updates").foregroundStyle(p.fair)
                        }
                        .buttonStyle(.plain)
                        .help("Check for a new version now (u in the ribbon)")
                        Button { ui.onQuit() } label: { Text("Quit").foregroundStyle(p.mist) }
                            .buttonStyle(.plain)
                            .help("Quit Halfpast (⌘Q in the ribbon)")
                    }
                    .font(hanken(12, .semibold))
                    .padding(.trailing, 14)
                    if snapshotMode {
                        Text("Open at login").font(hanken(12, .semibold)).foregroundStyle(p.mist)
                        Capsule().fill(p.button).frame(width: 26, height: 15)
                            .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 12).padding(.trailing, 1.5) }
                    } else {
                    Toggle(isOn: Binding(get: { loginOn }, set: { LoginItem.set($0); loginOn = LoginItem.enabled })) {
                        Text("Open at login").font(hanken(12, .semibold)).foregroundStyle(p.mist)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(p.button)
                    }
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 30)
            .padding(.bottom, 18)
            .frame(width: Metrics.panelWidth, height: 540, alignment: .topLeading)
        }
        .onAppear { if store.config.places.count < Store.maxPlaces { searching = true } }
    }

    // MARK: your places

    private func placeRow(_ i: Int, _ p: Palette) -> some View {
        let place = store.config.places[i]
        let row = store.places[i]
        let home = store.isHome(i)
        let favourite = store.isFavourite(i)
        let n = store.config.places.count
        return HStack(spacing: 10) {
            // Star = favourite (beside the notch); the house appears only on favourites, and
            // is filled on the one that is home.
            HStack(spacing: 2) {
                Button { store.toggleFavourite(i) } label: {
                    Image(systemName: favourite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(favourite ? p.fair : p.mist)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!home)
                .help(home ? "Home is always a favourite" : favourite ? "Favourite — beside the notch. Click to unstar" : "Make this a favourite, beside the notch")

                Button { store.setHome(i) } label: {
                    Image(systemName: home ? "house.fill" : "house")
                        .font(.system(size: 13))
                        .foregroundStyle(home ? p.homeTime : p.mist)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(favourite ? 1 : 0)
                .allowsHitTesting(favourite && !home)
                .help(home ? "Home" : "Make this home")
            }

            VStack(alignment: .leading, spacing: 2) {
                if snapshotMode {
                    Text(place.label).font(hanken(15, .semibold))
                } else {
                TextField("Name", text: Binding(
                    get: { i < store.config.places.count ? store.config.places[i].label : "" },
                    set: { if !$0.trimmingCharacters(in: .whitespaces).isEmpty, i < store.config.places.count { store.rename(i, to: $0) } }))
                    .textFieldStyle(.plain)
                    .font(hanken(15, .semibold))
                }
                Text([place.zone.isEmpty ? (store.away ? "Home time while you travel" : "Follows this Mac") : place.zone.replacingOccurrences(of: "_", with: " "),
                      row.abbr(at: store.now), store.time(store.now, row), "works \(row.hoursText) \(row.daysText)"].joined(separator: " · "))
                    .font(hanken(12)).foregroundStyle(p.mist).lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                iconButton("calendar.badge.clock", p, tint: editing == i ? p.fair : nil, enabled: true) { editing = editing == i ? nil : i }
                    .help("Working hours, days and holidays")
                if home {
                    Text("always first").font(hanken(11)).foregroundStyle(p.mist)
                        .frame(width: 84, alignment: .trailing)
                } else {
                    iconButton("chevron.up", p, enabled: i > 1) { store.move(i, by: -1); if editing == i { editing = i - 1 } }.help("Move up")
                    iconButton("chevron.down", p, enabled: i < n - 1) { store.move(i, by: 1); if editing == i { editing = i + 1 } }.help("Move down")
                    iconButton("minus.circle.fill", p, tint: Trilegal.red, enabled: true) { editing = nil; store.remove(i) }.help("Remove")
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(home ? p.homeTime.opacity(0.55) : favourite ? p.fair.opacity(0.5) : p.chipBorder))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.config.places.map(\.label))
    }

    private func iconButton(_ name: String, _ p: Palette, tint: Color? = nil, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ?? p.mist)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    // MARK: a place's working week

    /// Hours (half-hour steps), working days, public holidays and days off for one place — shown
    /// in place of the search while it is open.
    private func week(_ i: Int, _ p: Palette) -> some View {
        let row = store.places[i]
        let place = store.config.places[i]
        let country = Country.code(forZone: row.tz.identifier)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(place.label) — working week").font(hanken(13, .semibold)).foregroundStyle(p.mist)
                Spacer()
                Button { editing = nil } label: {
                    Text(store.config.places.count < Store.maxPlaces ? "Add a place" : "Close").font(hanken(12, .semibold)).foregroundStyle(p.fair)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Hours").font(hanken(13, .semibold)).frame(width: 64, alignment: .leading)
                    stepper(row.work.start, p) { store.nudgeWork(i, start: true, by: $0) }
                    Text("to").font(hanken(13)).foregroundStyle(p.mist)
                    stepper(row.work.end, p) { store.nudgeWork(i, start: false, by: $0) }
                }
                HStack(spacing: 10) {
                    Text("Days").font(hanken(13, .semibold)).frame(width: 64, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                            let on = row.workdays.contains(d)
                            Button { store.toggleWorkday(i, d) } label: {
                                Text(["S", "M", "T", "W", "T", "F", "S"][d - 1])
                                    .font(hanken(12, .bold))
                                    .foregroundStyle(on ? .white : p.mist)
                                    .frame(width: 28, height: 28)
                                    .background(on ? p.button : p.chip, in: Circle())
                                    .overlay(Circle().strokeBorder(on ? .clear : p.chipBorder))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d - 1])
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.chip, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Public holidays").font(hanken(13, .semibold))
                    Spacer()
                    toggle(place.holidays != false, p) { store.setHolidays(i, $0) }
                }
                Group {
                    if let c = country {
                        if place.holidays == false {
                            Text("Off — \(Country.name(c))'s holidays are left out.")
                        } else if Holidays.shared.days[c] == nil {
                            Text(Holidays.shared.missing.contains(c) ? "No holiday calendar found for \(Country.name(c))." : "Fetching \(Country.name(c))'s holidays…")
                        } else {
                            let next = Holidays.shared.upcoming(c, from: Holidays.key(store.now, row.cal))
                            Text("\(Country.name(c)), from Google's public calendar. Next: " + next.map { "\($0.1.name) \(short($0.0))" }.joined(separator: " · "))
                        }
                    } else {
                        Text("No country for this time zone.")
                    }
                }
                .font(hanken(12)).foregroundStyle(p.mist)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.chip, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Days off").font(hanken(13, .semibold))
                    Spacer()
                    if snapshotMode {
                        Text(short(Holidays.key(newDayOff, .current))).font(hanken(13))
                    } else {
                        DatePicker("", selection: $newDayOff, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .font(hanken(13))
                    }
                    pillButton("Add", p) { store.addDayOff(i, Holidays.key(newDayOff, .current)) }
                }
                let mine = (place.daysOff ?? []).filter { $0 >= Holidays.key(store.now, row.cal) }
                if mine.isEmpty {
                    Text("Office closures or leave that count as days off for \(place.label).").font(hanken(12)).foregroundStyle(p.mist)
                } else {
                    HStack(spacing: 6) {
                        ForEach(mine.prefix(5), id: \.self) { k in
                            Button { store.removeDayOff(i, k) } label: {
                                HStack(spacing: 4) { Text(short(k)); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                    .font(hanken(12, .semibold)).foregroundStyle(p.offText)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(p.off, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Remove this day off")
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.chip, in: RoundedRectangle(cornerRadius: 12))

            if place.work != nil || place.workdays != nil || place.holidays == false {
                Button { store.resetWeek(i) } label: {
                    Text("Back to 8–18, \(Country.workingDays(country) == [2, 3, 4, 5, 6] ? "Monday to Friday" : "the usual week"), with holidays")
                        .font(hanken(12)).foregroundStyle(p.fair)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Sun 8 Nov" from yyyy-MM-dd.
    private func short(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    private func stepper(_ h: Double, _ p: Palette, _ by: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 2) {
            iconButton("minus", p, enabled: true) { by(-0.5) }
            Text(String(format: "%02d:%02d", Int(h), Int((h.truncatingRemainder(dividingBy: 1) * 60).rounded())))
                .font(hanken(14, .semibold)).frame(width: 50)
            iconButton("plus", p, enabled: true) { by(0.5) }
        }
        .padding(2)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.chipBorder))
    }

    private func pillButton(_ label: String, _ p: Palette, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(hanken(12, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(p.button, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func toggle(_ on: Bool, _ p: Palette, _ set: @escaping (Bool) -> Void) -> some View {
        if snapshotMode {
            Capsule().fill(on ? p.button : p.chipBorder).frame(width: 26, height: 15)
                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 12).padding(.horizontal, 1.5) }
        } else {
            Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(p.button)
        }
    }

    // MARK: adding

    private func searchField(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(p.mist)
            if snapshotMode {
                Text(query.isEmpty ? "A city — Tokyo, Nairobi, Toronto…" : query).font(hanken(15))
                    .foregroundStyle(query.isEmpty ? p.mist : p.text)
                Spacer()
            } else {
            TextField("A city — Tokyo, Nairobi, Toronto…", text: $query)
                .textFieldStyle(.plain)
                .font(hanken(15))
                .focused($searching)
                .onSubmit { if let first = matches.first { add(first) } }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(searching ? p.fair : p.chipBorder))
        .onChange(of: query) { _ in remote = [] }
    }

    private var matches: [City] {
        let local = Cities.search(query).filter { !store.has($0) }
        return Array((local.isEmpty ? remote.filter { !store.has($0) } : local).prefix(6))
    }

    @ViewBuilder private func results(_ p: Palette) -> some View {
        let found = matches
        VStack(alignment: .leading, spacing: 6) {
            ForEach(found) { city in
                Button { add(city) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(city.name).font(hanken(14, .semibold))
                            Text(describe(city)).font(hanken(12)).foregroundStyle(p.mist).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(p.fair)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(p.chip, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if found.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 3 {
                Button {
                    lookingUp = true
                    let q = query
                    Task {
                        let r = await Cities.lookUp(q)
                        if query == q { remote = r }
                        lookingUp = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: lookingUp ? "hourglass" : "map")
                        Text(lookingUp ? "Looking up “\(query)”…" : "Not in the list — look up “\(query)” with Apple Maps")
                    }
                    .font(hanken(13)).foregroundStyle(p.fair)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func describe(_ city: City) -> String {
        guard let tz = TimeZone(identifier: city.zone) else { return city.country }
        let row = Row(id: -1, label: city.name, short: city.short, tz: tz, abbr: nil, isHome: false)
        return [city.country, row.abbr(at: store.now), store.time(store.now, row), store.diff(row, at: store.now)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func add(_ city: City) {
        store.add(city)
        query = ""
        remote = []
        if store.config.places.count < Store.maxPlaces { searching = true }
    }

    // MARK: appearance

    private func appearancePicker(_ p: Palette) -> some View {
        let options = [("system", "Match Mac", "circle.lefthalf.filled"), ("light", "Light", "sun.max"), ("dark", "Dark", "moon")]
        return HStack(spacing: 2) {
            ForEach(options, id: \.0) { key, label, icon in
                let on = store.config.appearance == key
                Button { store.setAppearance(key) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                        Text(label)
                    }
                    .font(hanken(12, on ? .semibold : .regular))
                    .foregroundStyle(on ? .white : p.mist)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(on ? p.button : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.chipBorder))
    }
}
