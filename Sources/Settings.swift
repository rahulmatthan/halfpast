import SwiftUI

/// Places & appearance, shown in the same glass panel in place of the ribbon: the places you
/// have (rename, reorder, pin two to the notch, remove), a search to add one while there is
/// room, and light / dark / match the Mac.
struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var remote: [City] = []
    @State private var lookingUp = false
    @FocusState private var searching: Bool

    var body: some View {
        let p = Palette.of(scheme)
        PanelChrome {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text("Places & appearance").font(hanken(22, .semibold))
                    Spacer()
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
                .padding(.top, 22)

                Spacer(minLength: 12)
                (Text(Image(systemName: "star.fill")).foregroundColor(p.fair) + Text("  Two favourites sit either side of the notch.     ")
                    + Text(Image(systemName: "house.fill")).foregroundColor(p.homeTime) + Text("  One of them is home: the top row, and the clock every other place is measured from."))
                    .font(hanken(12)).foregroundStyle(p.mist)
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
                TextField("Name", text: Binding(
                    get: { i < store.config.places.count ? store.config.places[i].label : "" },
                    set: { if !$0.trimmingCharacters(in: .whitespaces).isEmpty, i < store.config.places.count { store.rename(i, to: $0) } }))
                    .textFieldStyle(.plain)
                    .font(hanken(15, .semibold))
                Text(place.zone.isEmpty ? "Follows this Mac · \(row.abbr(at: store.now)) · \(store.time(store.now, row))"
                          : "\(place.zone.replacingOccurrences(of: "_", with: " ")) · \(row.abbr(at: store.now)) · \(store.time(store.now, row))")
                    .font(hanken(12)).foregroundStyle(p.mist).lineLimit(1)
            }

            Spacer(minLength: 4)

            if home {
                Text("always first").font(hanken(11)).foregroundStyle(p.mist)
                    .frame(width: 84, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    iconButton("chevron.up", p, enabled: i > 1) { store.move(i, by: -1) }.help("Move up")
                    iconButton("chevron.down", p, enabled: i < n - 1) { store.move(i, by: 1) }.help("Move down")
                    iconButton("minus.circle.fill", p, tint: Trilegal.red, enabled: true) { store.remove(i) }.help("Remove")
                }
                .frame(width: 84, alignment: .trailing)
            }
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

    // MARK: adding

    private func searchField(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(p.mist)
            TextField("A city — Tokyo, Nairobi, Toronto…", text: $query)
                .textFieldStyle(.plain)
                .font(hanken(15))
                .focused($searching)
                .onSubmit { if let first = matches.first { add(first) } }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(searching ? p.fair : p.chipBorder))
        .onChange(of: query) { remote = [] }
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
