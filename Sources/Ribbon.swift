import AppKit
import SwiftUI

/// The Trilegal ribbon colours.
enum Trilegal {
    static let navy = Color(hex: 0x004165)
    static let teal = Color(hex: 0x0094B3)
    static let red = Color(hex: 0xAA272F)
    static let orange = Color(hex: 0xFF6D22)
    static let grey = Color(hex: 0x636467)
    static let mist = Color(hex: 0xC3D0DC)      // secondary text on the black notch
    static let ribbon = [navy, teal, red, orange, grey]
}

/// The panel's colours by light and dark: navy glass at night, pale glass by day, the same
/// Trilegal accents in both.
struct Palette {
    let tint: Color, tintOpacity: Double, material: NSVisualEffectView.Material
    let text, mist: Color
    let work, workText, awake, awakeText, asleep, asleepText, selected: Color
    let off, offText: Color         // working hours on a weekend or holiday
    let now, fair, homeTime, proposed: Color
    let border, chip, chipBorder, button: Color

    static let dark = Palette(
        tint: Color(hex: 0x081E32), tintOpacity: 0.74, material: .hudWindow,
        text: .white, mist: Color(hex: 0xC3D0DC),
        work: Trilegal.teal.opacity(0.62), workText: .white, awake: .white.opacity(0.13), awakeText: .white,
        asleep: .white.opacity(0.04), asleepText: Color(hex: 0x8EA2B5), selected: Trilegal.red.opacity(0.92),
        off: Trilegal.orange.opacity(0.24), offText: Color(hex: 0xFFC9A8),
        now: Trilegal.orange, fair: Color(hex: 0x3EC5E4), homeTime: Trilegal.orange, proposed: Color(hex: 0xF0707A),
        border: .white.opacity(0.2), chip: .white.opacity(0.10), chipBorder: .white.opacity(0.18), button: Trilegal.teal.opacity(0.7))

    static let light = Palette(
        tint: Color(hex: 0xF5F8FB), tintOpacity: 0.72, material: .popover,
        text: Color(hex: 0x182B49), mist: Color(hex: 0x5A6270),
        work: Color(hex: 0x007C97), workText: .white, awake: Trilegal.navy.opacity(0.08), awakeText: Color(hex: 0x182B49),
        asleep: Trilegal.navy.opacity(0.03), asleepText: Color(hex: 0x8A93A3), selected: Trilegal.red,
        off: Trilegal.orange.opacity(0.16), offText: Color(hex: 0xB4471A),
        now: Trilegal.orange, fair: Trilegal.teal, homeTime: Color(hex: 0xD9531E), proposed: Trilegal.red,
        border: Trilegal.navy.opacity(0.14), chip: Trilegal.navy.opacity(0.05), chipBorder: Trilegal.navy.opacity(0.12), button: Color(hex: 0x007C97))

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

func hanken(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Hanken Grotesk", size: size).weight(weight).monospacedDigit()
}

/// The frosted glass behind the panel: the desktop blurred, then tinted.
struct Frost: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Set when rendering screenshots (HALFPAST_* in AppDelegate): plain fills instead of glass, and
/// text fields drawn as text, since ImageRenderer can draw neither.
@MainActor var snapshotMode = ["HALFPAST_SNAPSHOT", "HALFPAST_NOTCH", "HALFPAST_SETTINGS", "HALFPAST_WELCOME"]
    .contains { ProcessInfo.processInfo.environment[$0] != nil }     // set before anything loads or saves

/// What the ribbon and the settings view share: the glass, its edge, and the Trilegal ribbon
/// along the bottom.
struct PanelChrome<Content: View>: View {
    var solid = false       // the copy-as-picture version: no desktop to blur, so a plain fill
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        let shape = solid
            ? UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 26, bottomTrailing: 26, topTrailing: 18))
            : UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 26, bottomTrailing: 26, topTrailing: 0))
        VStack(alignment: .leading, spacing: 0) {
            content
            HStack(spacing: 0) {
                ForEach(Trilegal.ribbon.indices, id: \.self) { Trilegal.ribbon[$0] }
            }
            .frame(height: 6)
        }
        .foregroundStyle(p.text)
        .background {
            if solid || snapshotMode { p.tint } else { ZStack { Frost(material: p.material); p.tint.opacity(p.tintOpacity) } }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(p.border, lineWidth: 1))
        .fixedSize()
    }
}

enum Metrics {
    static let pad: CGFloat = 28
    static let header: CGFloat = 236
    static let headerGap: CGFloat = 18
    static let cell: CGFloat = 30
    static let gap: CGFloat = 2
    static let cellHeight: CGFloat = 44
    static let rowHeight: CGFloat = 56
    static let rowGap: CGFloat = 8
    static let top: CGFloat = 40
    static var pitch: CGFloat { cell + gap }
    static var gridX: CGFloat { pad + header + headerGap }
    static var gridWidth: CGFloat { 24 * cell + 23 * gap }
    static var panelWidth: CGFloat { gridX + gridWidth + pad }
    static let hiddenHeight: CGFloat = 26

    /// Height of the rows, with hidden ones folded down to a thin line.
    static func rowsHeight(_ hidden: [Bool]) -> CGFloat {
        hidden.reduce(0) { $0 + ($1 ? hiddenHeight : rowHeight) } + CGFloat(max(hidden.count - 1, 0)) * rowGap
    }

    /// Where a moment (hours after the grid's midnight) falls across the cells and their gaps.
    static func x(_ hours: Double) -> CGFloat {
        let h = min(max(hours, 0), 24)
        let col = min(floor(h), 23)
        return gridX + CGFloat(col) * pitch + CGFloat(min(h - col, 1)) * cell + (h >= 24 ? gap : 0)
    }
}

/// The glass ribbon that drops out of the notch: one 24-hour strip per place, columns on
/// the same moment, the fairest hour outlined.
struct RibbonPanel: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    var solid = false
    var hints = true
    var onCopyInvite: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @FocusState private var typing: Bool
    @State private var hoveredRow: Int?

    var body: some View {
        let p = Palette.of(scheme)
        let rows = store.rows
        let focus = store.focus
        let fair = store.fairestCol
        let slide = -CGFloat(store.scroll) * Metrics.pitch     // now kept in the middle: everything drifts left
        let rowsHeight = Metrics.rowsHeight(rows.map(store.isHidden))
        PanelChrome(solid: solid) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: Metrics.rowGap) {
                    ForEach(rows) { row in
                        if store.isHidden(row) {
                            hiddenRow(row, p)
                        } else {
                            HStack(spacing: Metrics.headerGap) {
                                header(row, focus, p).frame(width: Metrics.header, alignment: .leading)
                                strip(row, p)
                            }
                            .frame(height: Metrics.rowHeight)
                            .onHover { hoveredRow = $0 ? row.id : (hoveredRow == row.id ? nil : hoveredRow) }
                        }
                    }
                }
                .padding(.top, Metrics.top)
                .padding(.horizontal, Metrics.pad)

                if !solid { daySwitcher(p).offset(x: Metrics.pad, y: 8) }
                else { Text(store.date(store.shownDay, store.homeRow)).font(hanken(13, .semibold)).offset(x: Metrics.pad, y: 12) }

                if store.proposal == nil && store.columns.contains(fair) {
                    Text("FAIREST")
                        .font(hanken(11, .bold))
                        .foregroundStyle(p.fair)
                        .frame(width: 80)
                        .offset(x: Metrics.gridX + (CGFloat(fair) + 0.5) * Metrics.pitch - 40 + slide, y: 14)
                }
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(p.fair.opacity(!store.columns.contains(fair) ? 0 : store.proposal == nil ? 1 : 0.45), lineWidth: 2)
                    .frame(width: Metrics.cell + 4, height: rowsHeight + 12)
                    .offset(x: Metrics.gridX + CGFloat(fair) * Metrics.pitch - 2 + slide, y: Metrics.top - 6)
                    .allowsHitTesting(false)
                if store.proposal == nil, let hc = store.hoverCol {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(p.text.opacity(0.5), lineWidth: 1.5)
                        .frame(width: Metrics.cell + 2, height: rowsHeight + 4)
                        .offset(x: Metrics.gridX + CGFloat(hc) * Metrics.pitch - 1 + slide, y: Metrics.top - 2)
                        .allowsHitTesting(false)
                }
                nowLine(height: rowsHeight + 16, p).offset(x: slide)
                block(height: rowsHeight, p).offset(x: slide)
            }
            .frame(width: Metrics.panelWidth, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt):
                    let x = pt.x - Metrics.gridX
                    store.hoverCol = x >= 0 && x < Metrics.gridWidth && pt.y > Metrics.top - 8 ? store.column(atX: x, pitch: Metrics.pitch) : nil
                case .ended: store.hoverCol = nil
                }
            }
            // Clicks and drags on the grid are handled in AppDelegate (gridMouse), where they
            // work reliably in a panel that never activates the app.

            bar(p).padding(.horizontal, Metrics.pad).padding(.top, 18)

            if hints {
                HStack(spacing: 10) {
                    if store.flash == nil && store.away && (!solid || snapshotMode) {
                        travel(p)
                    } else {
                        Text(store.flash ?? "Click an hour  ·  ← → nudge 5 min (⇧ an hour)  ·  drag the block  ·  type: 7:30am NY tue  ·  [ ] day  ·  d length  ·  n clear")
                            .foregroundStyle(store.flash == nil ? p.mist : p.fair)
                    }
                    Spacer()
                    if let v = ui.updateReady, !solid || snapshotMode {
                        pill("Update to \(v)", p, strong: true) { ui.onUpdates() }
                            .help("Halfpast \(v) is ready (u)")
                    }
                    Button { ui.settingsShown = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text("Places & appearance")
                        }
                        .foregroundStyle(p.mist)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add, remove or pin places; light or dark (s)")
                }
                .font(hanken(12))
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 12)
                .padding(.bottom, 14)
            } else {
                Spacer().frame(height: 18)
            }
        }
    }

    /// Away from home: where the Mac's clock is, and which place the grid is measured from.
    private func travel(_ p: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane").foregroundStyle(p.fair)
            if store.travelUndecided {
                Text("This Mac is on \(store.hereName) time.").foregroundStyle(p.text)
                pill("Plan from \(store.hereName)", p, strong: true) { store.planFromHere(true) }
                pill("Keep \(store.homeName)", p) { store.planFromHere(false) }
            } else if store.planningHere {
                Text("Planning from \(store.hereName) while you travel").foregroundStyle(p.mist)
                pill("Plan from \(store.homeName)", p) { store.planFromHere(false) }
            } else {
                Text("On \(store.hereName) time · planning from \(store.homeName)").foregroundStyle(p.mist)
                pill("Plan from \(store.hereName)", p) { store.planFromHere(true) }
            }
        }
    }

    private func pill(_ label: String, _ p: Palette, strong: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(hanken(12, .semibold))
                .foregroundStyle(strong ? .white : p.text)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(strong ? p.button : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(strong ? .clear : p.chipBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func header(_ row: Row, _ focus: Date, _ p: Palette) -> some View {
        let off = store.dayOff(row, at: focus)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(store.time(focus, row))
                .font(hanken(store.format.twelve ? 22 : 27, .light))
                .foregroundStyle(row.isHome ? p.homeTime : p.text)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.label).font(hanken(15, .semibold)).lineLimit(1).layoutPriority(1)
                    if let off {
                        // A weekend, a holiday or a day off where this place is, at the moment shown;
                        // weekends quietly, the rest in the holiday colour.
                        let quiet: Bool = { if case .weekend = off { return true }; return false }()
                        Text(off.off ? off.name : "\(off.name)?")
                            .font(hanken(11, .semibold))
                            .foregroundStyle(quiet ? p.mist : p.offText)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(quiet ? p.chip : p.off, in: Capsule())
                            .help(offHelp(off, row))
                    }
                }
                Text(meta(row, focus)).font(hanken(12)).foregroundStyle(p.mist).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if hoveredRow == row.id && !solid {
                Button { store.toggleHidden(row) } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(p.mist)
                        .frame(width: 24, height: 24)
                        .background(p.chip, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Hide \(row.label) for now — left out of the email and the fairest hour")
            }
        }
    }

    /// A hidden place, folded to a thin line; click to bring it back.
    private func hiddenRow(_ row: Row, _ p: Palette) -> some View {
        Button { store.toggleHidden(row) } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                Text(row.label).font(hanken(12, .semibold))
                Text("hidden — not in the email or the fairest hour · click to show").font(hanken(12))
            }
            .foregroundStyle(p.mist)
            .padding(.horizontal, 12)
            .frame(height: Metrics.hiddenHeight)
            .background(p.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func offHelp(_ d: DayOff, _ row: Row) -> String {
        switch d {
        case .weekend: return "Not a working day in \(row.label)"
        case .holiday(let n): return "\(n): a public holiday in \(row.country.map(Country.name) ?? row.label)"
        case .ownDay: return "A day off you added for \(row.label)"
        case .regional(let n, let w): return "\(n): a holiday in \(w) only"
        }
    }

    private func meta(_ row: Row, _ focus: Date) -> String {
        [row.abbr(at: focus), store.date(focus, row), store.diff(row, at: focus)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A place's strip: one cell per hour of its own clock. Where its clock is off home's by half
    /// an hour (or 45 minutes), the cells sit that far off home's columns, half cells showing at
    /// either end — the stagger the app is named for. Columns, the fairest hour, the now line and
    /// the proposed block stay on home's time and cut straight through.
    private func strip(_ row: Row, _ p: Palette) -> some View {
        let m = row.cal.component(.minute, from: store.dayStart)   // minutes past its hour at the grid's start
        let lead = Double(m) / 60 + store.scroll                     // columns its first cell starts left of the grid
        return HStack(spacing: Metrics.gap) {
            ForEach(0..<(lead == 0 ? 24 : 25), id: \.self) { k in
                // Cells cut by either edge keep their colour but not their number.
                let x = (Double(k) - lead) * Metrics.pitch
                cell(row, store.dayStart.addingTimeInterval(Double(k) * 3600 - Double(m) * 60), p,
                     label: x > -1 && x + Metrics.cell < Metrics.gridWidth + 1)
            }
        }
        .offset(x: -CGFloat(lead) * Metrics.pitch)
        .frame(width: Metrics.gridWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // The ends fade, as if the strip runs on into yesterday and tomorrow.
        .mask(LinearGradient(stops: [.init(color: .black.opacity(0.12), location: 0), .init(color: .black, location: 0.075),
                                     .init(color: .black, location: 0.925), .init(color: .black.opacity(0.12), location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }

    private func cell(_ row: Row, _ at: Date, _ p: Palette, label: Bool = true) -> some View {
        let c = row.cal.dateComponents([.hour, .day, .weekday], from: at)
        let hour = c.hour ?? 0
        let phase = store.phase(row, at: at, mid: true)
        let fill = [Phase.work: p.work, .off: p.off, .awake: p.awake, .asleep: p.asleep][phase]!
        let ink = [Phase.work: p.workText, .off: p.offText, .awake: p.awakeText, .asleep: p.asleepText][phase]!
        return ZStack {
            fill
            if !label {
                EmptyView()
            } else if hour == 0 {
                // Midnight: the new day's name, so the date line reads across the rows.
                VStack(spacing: 0) {
                    Text(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(c.weekday ?? 1) - 1])
                    Text("\(c.day ?? 1)")
                }
                .font(hanken(10, .bold))
                .foregroundStyle(p.text)
            } else {
                Text(store.hourLabel(hour))
                    .font(hanken(store.format.twelve ? 11 : 13, .medium))
                    .foregroundStyle(ink)
            }
        }
        .frame(width: Metrics.cell, height: Metrics.cellHeight)
    }

    /// ‹ Tue 20 Oct ›, with Today to come back — the day the grid shows.
    private func daySwitcher(_ p: Palette) -> some View {
        HStack(spacing: 6) {
            Button { store.changeDay(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Previous day ([)")
            Text(store.dayOffset == 0 ? "Today · \(store.date(store.shownDay, store.homeRow))" : store.date(store.shownDay, store.homeRow))
                .font(hanken(13, .semibold))
                .foregroundStyle(store.dayOffset == 0 ? p.mist : p.text)
                .frame(minWidth: 112)
            Button { store.changeDay(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Next day (])")
            if store.dayOffset != 0 {
                Button { store.changeDay(by: -store.dayOffset) } label: {
                    Text("Today").font(hanken(12, .semibold)).foregroundStyle(p.fair)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(p.mist)
    }

    @ViewBuilder private func nowLine(height: CGFloat, _ p: Palette) -> some View {
        if store.dayOffset == 0 { nowMark(height: height, p) }
    }

    private func nowMark(height: CGFloat, _ p: Palette) -> some View {
        let hours = store.now.timeIntervalSince(store.dayStart) / 3600
        let col = floor(hours)
        let x = Metrics.gridX + col * Metrics.pitch + (hours - col) * Metrics.cell
        return Capsule()
            .fill(p.now)
            .frame(width: 2, height: height)
            .shadow(color: p.now.opacity(0.7), radius: 4)
            .offset(x: x - 1, y: Metrics.top - 8)
    }

    /// The proposed hour: a block across every row from its start to an hour later, sliding
    /// into the next hour as it is nudged (6:10 covers 6:10–7:10).
    @ViewBuilder private func block(height: CGFloat, _ p: Palette) -> some View {
        if let t = store.proposal {
            let h0 = t.timeIntervalSince(store.dayStart) / 3600
            let x0 = Metrics.x(h0), x1 = Metrics.x(h0 + Double(store.duration) / 60)
            RoundedRectangle(cornerRadius: 8)
                .fill(p.selected.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.selected, lineWidth: 2))
                .frame(width: x1 - x0 + 4, height: height + 8)
                .offset(x: x0 - 2, y: Metrics.top - 4)
                .allowsHitTesting(false)
            Text(store.range(from: t, store.homeRow))
                .font(hanken(11, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(p.selected, in: Capsule())
                .fixedSize()
                .frame(width: 140)
                .offset(x: (x0 + x1) / 2 - 70, y: 12)
                .allowsHitTesting(false)
        }
    }

    /// The bottom bar: the fairest hour; a field while he types a time; or the hour he is
    /// proposing, with the 5-minute nudges and the copy for email.
    private func bar(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if store.timeQuery != nil {
                    Image(systemName: "clock").foregroundStyle(p.fair)
                    TextField("6:15 India · 7:30am NY · 18:00 London", text: Binding(
                        get: { store.timeQuery ?? "" },
                        set: { store.timeQuery = $0; store.preview() }))
                        .textFieldStyle(.plain)
                        .font(hanken(15, .semibold))
                        .focused($typing)
                        .onSubmit { store.finishTyping(keep: true) }
                        .onAppear { typing = true }
                    Spacer(minLength: 8)
                    Text(store.timeQueryValid ? "return to keep · esc to cancel" : "a time, then a place — or leave the place out for home")
                        .font(hanken(12)).foregroundStyle(p.mist)
                } else if let t = store.proposal {
                    Image(systemName: "clock.fill").foregroundStyle(p.proposed)
                    (Text("Proposed   ").font(hanken(14, .bold)).foregroundColor(p.proposed)
                        + Text("\(store.range(from: t, store.homeRow)) \(store.homeRow.label)").font(hanken(14, .semibold)))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !solid {
                        durationPicker(p)
                        nudge("chevron.left", "5 min", p) { store.step(minutes: -5) }
                        nudge("chevron.right", "5 min", p, trailing: true) { store.step(minutes: 5) }
                        Button { store.backToNow() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(p.mist)
                        }
                        .buttonStyle(.plain)
                        .help("Clear the proposed time (n)")
                        copyButton(p)
                    }
                } else {
                    Image(systemName: "person.3.fill").foregroundStyle(p.fair)
                    // Past the edge (now in the middle): say which day, and that f goes there.
                    let ahead = !store.columns.contains(store.fairestCol)
                    (Text("Fairest hour   ").font(hanken(14, .bold)).foregroundColor(p.fair)
                        + Text(ahead ? "\(store.date(store.instant(store.fairestCol), store.homeRow)) · " : "").font(hanken(14, .semibold))
                        + Text(store.summary(at: store.instant(store.fairestCol))).font(hanken(14))
                        + Text(ahead ? "   f to go there" : "").font(hanken(12)).foregroundColor(p.mist))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !solid { copyButton(p) }
                }
            }
            if store.timeQuery == nil, let t = store.proposal {
                Text(store.summary(at: t)).font(hanken(13)).foregroundStyle(p.mist).lineLimit(1)
            }
            if store.timeQuery == nil {
                let notes = store.offNotes(at: store.proposal ?? store.instant(store.fairestCol))
                if !notes.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                        Text(notes.joined(separator: "  ·  ")).lineLimit(1)
                    }
                    .font(hanken(12, .semibold))
                    .foregroundStyle(p.offText)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(minHeight: 46)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(store.timeQuery != nil ? p.fair : store.proposal != nil ? p.selected.opacity(0.6) : p.chipBorder))
    }

    private func nudge(_ icon: String, _ label: String, _ p: Palette, trailing: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !trailing { Image(systemName: icon) }
                Text(label)
                if trailing { Image(systemName: icon) }
            }
            .font(hanken(12, .semibold))
            .foregroundStyle(p.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(p.chip, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.chipBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(trailing ? "Later by 5 minutes (→)" : "Earlier by 5 minutes (←)")
    }

    /// 15 · 30 · 45 · 60 — how long the proposed meeting is (d cycles).
    private func durationPicker(_ p: Palette) -> some View {
        HStack(spacing: 2) {
            ForEach(Store.durations, id: \.self) { m in
                let on = store.duration == m
                Button { store.setDuration(m) } label: {
                    Text(m == 60 ? "1 h" : "\(m)")
                        .font(hanken(12, on ? .bold : .medium))
                        .foregroundStyle(on ? .white : p.mist)
                        .frame(width: 32, height: 24)
                        .background(on ? p.button : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(m == 60 ? "1 hour" : "\(m) minutes") meeting (d)")
            }
        }
        .padding(2)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.chipBorder))
    }

    private func copyButton(_ p: Palette) -> some View {
        Button(action: onCopyInvite) {
            HStack(spacing: 6) { Image(systemName: "envelope"); Text("Copy for email") }
                .font(hanken(13, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(p.button, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .help("Copies each place's hour, start to end, ready to paste into an email")
    }
}
