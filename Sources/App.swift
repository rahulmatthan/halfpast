import AppKit
import Combine
import CoreText
import Carbon.HIToolbox
import Sparkle
import SwiftUI

@main
struct HalfpastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

/// A borderless panel that takes the keyboard without pulling focus from the app you were in.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Takes the first click even though the panel never activates the app — otherwise a click on
/// the notch would only focus it.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The ribbon (or the settings in its place), dropping from the top edge as it appears.
struct PanelHost: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    var onCopyInvite: () -> Void

    var body: some View {
        Group {
            if ui.welcomeShown {
                WelcomeView(store: store, ui: ui) { setUp in
                    store.markWelcomed()
                    ui.welcomeShown = false
                    ui.settingsShown = setUp
                }
            } else if ui.settingsShown {
                SettingsView(store: store, ui: ui)
            } else {
                RibbonPanel(store: store, ui: ui, onCopyInvite: onCopyInvite)
            }
        }
            .scaleEffect(x: ui.panelShown ? 1 : 0.94, y: ui.panelShown ? 1 : 0.8, anchor: .top)
            .opacity(ui.panelShown ? 1 : 0)
            .offset(y: ui.panelShown ? 0 : -8)
    }
}

/// No menu bar icon: hovering at the notch grows a black cap with two times either side of the
/// camera; clicking it (or ⌃⌥T) drops the glass ribbon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let ui = NotchUI()
    private var notch: NSRect = .zero           // the camera housing, in screen coordinates
    private var screen: NSScreen?
    private var cap: KeyPanel!
    private var panel: KeyPanel!
    private var panelHost: FirstClickHostingView<PanelHost>!
    private var hotkey: Hotkey?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var poll: Timer?
    private var dwell = 0, away = 0
    private var watches: Set<AnyCancellable> = []
    private var mouseMonitor: Any?
    private var drag: (x: CGFloat, from: Date)?   // a block being dragged: where the press began
    private let click = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // The typeface travels inside the app, so it looks the same on Macs that don't have it.
        if let font = Bundle.main.url(forResource: "HankenGrotesk", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
        findNotch()

        // HALFPAST_SNAPSHOT=/path.png [HALFPAST_COL=n] [HALFPAST_FORMAT=utc] [HALFPAST_LIGHT=1] renders the ribbon to a
        // file and quits; HALFPAST_SETTINGS=/path.png renders the settings, HALFPAST_NOTCH=/path.png the open notch.
        // For checking layouts without Screen Recording permission.
        let env = ProcessInfo.processInfo.environment
        if env["HALFPAST_SNAPSHOT"] != nil || env["HALFPAST_NOTCH"] != nil || env["HALFPAST_SETTINGS"] != nil || env["HALFPAST_WELCOME"] != nil {
            snapshotMode = true     // also stops anything below saving his settings
            if env["HALFPAST_FIVE"] != nil {      // five places, so the settings show the search
                var c = store.config
                c.places.removeAll { $0.label == "San Francisco" }
                store.showWithoutSaving(c)
            }
            if let t = env["HALFPAST_TRAVEL"] {     // with TZ=Europe/London: "here", "home" or "ask"
                var c = store.config
                c.travel = t == "ask" ? nil : Travel(zone: TimeZone.current.identifier, here: t == "here")
                store.showWithoutSaving(c)
            }
            if env["HALFPAST_ROLL"] != nil { var c = store.config; c.rolling = true; store.showWithoutSaving(c) }
            ui.updateReady = env["HALFPAST_UPDATE"]     // e.g. 1.2: shows the update reminders
            if let c = env["HALFPAST_COL"].flatMap(Int.init) { store.propose(col: c) }
            if let m = env["HALFPAST_MINUTES"].flatMap(Int.init) { store.setDuration(m) }
            if let q = env["HALFPAST_TIME"], let t = TimeParser.parse(q, store: store) { store.show(t) }
            for name in (env["HALFPAST_HIDE"] ?? "").split(separator: ",") { store.hidden.insert(name.lowercased()) }
            if let f = env["HALFPAST_FORMAT"].flatMap(HourFormat.init) { store.format = f }
            ui.expanded = true; ui.showTimes = true; ui.panelShown = true
            let scheme: ColorScheme = env["HALFPAST_LIGHT"] != nil ? .light : .dark
            if let path = env["HALFPAST_SNAPSHOT"] {
                try? render(RibbonPanel(store: store, ui: ui, solid: true, hints: true).environment(\.colorScheme, scheme))?.write(to: URL(fileURLWithPath: path))
            }
            if let path = env["HALFPAST_SETTINGS"] {
                try? render(SettingsView(store: store, ui: ui, query: env["HALFPAST_QUERY"] ?? "", editing: env["HALFPAST_EDIT"].flatMap(Int.init)).background(scheme == .dark ? Color(hex: 0x081E32) : Color(hex: 0xF5F8FB))
                    .environment(\.colorScheme, scheme))?.write(to: URL(fileURLWithPath: path))
            }
            if let path = env["HALFPAST_WELCOME"] {
                try? render(WelcomeView(store: store, ui: ui) { _ in }.environment(\.colorScheme, scheme))?.write(to: URL(fileURLWithPath: path))
            }
            if let path = env["HALFPAST_NOTCH"] {
                try? render(NotchView(store: store, ui: ui).padding(30).background(Color(hex: 0x3A4A5A)))?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
            return
        }

        // Updates: Sparkle checks exmachina.in/halfpast/appcast.xml once a day (Info.plist) and
        // offers a new version when there is one.
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        }
        // Close the panel first: it hangs at status-bar level and would cover Sparkle's window.
        ui.onUpdates = { [weak self] in
            self?.closePanel()
            if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
            self?.updater?.checkForUpdates(nil)
        }

        ui.onTap = { [weak self] in self?.togglePanel() }
        ui.onSettings = { [weak self] in self?.openPanel(settings: true) }
        ui.onQuit = { NSApp.terminate(nil) }

        cap = makePanel(level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        cap.contentView = FirstClickHostingView(rootView: NotchView(store: store, ui: ui))
        cap.hasShadow = false

        panel = makePanel(level: .statusBar)
        panelHost = FirstClickHostingView(rootView: PanelHost(store: store, ui: ui) { [weak self] in self?.copyInvite() })
        panel.contentView = panelHost
        panel.hasShadow = true

        // Light, dark, or whatever the Mac is set to — the panel follows the system live when nil.
        store.$config.map(\.appearance).removeDuplicates().sink { [weak self] a in
            self?.panel.appearance = a == "light" ? NSAppearance(named: .aqua) : a == "dark" ? NSAppearance(named: .darkAqua) : nil
        }.store(in: &watches)
        // The settings view and the ribbon differ in height: re-hang the panel when they swap, and
        // when places are added or removed.
        ui.$settingsShown.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layoutPanel() } }.store(in: &watches)
        ui.$welcomeShown.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layoutPanel() } }.store(in: &watches)
        store.$config.map(\.places.count).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutPanel() }
        }.store(in: &watches)
        store.$config.map(\.travel).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutPanel() }
        }.store(in: &watches)
        store.$hidden.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutPanel() }
        }.store(in: &watches)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isVisible else { return e }
            return self.handleKey(e) ? nil : e
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
            self?.gridMouse(e) ?? e
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        hotkey = Hotkey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey, id: 1) { [weak self] in self?.togglePanel() }
        // Scripts and keybinding tools can open or close it too: post com.rahulmatthan.halfpast.toggle
        // (or com.rahulmatthan.halfpast.settings to open straight into Places & appearance).
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.rahulmatthan.halfpast.toggle"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.togglePanel() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.rahulmatthan.halfpast.settings"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openPanel(settings: true) }
        }

        // Twenty-five checks a second of where the pointer is: cheap, and unlike event monitors it
        // works the same over full-screen apps.
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchPointer() }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t

        // First run: open at login (switchable in Places & appearance) and say hello from the notch.
        if !store.config.welcomed {
            if Bundle.main.bundlePath.hasSuffix("/Applications/Halfpast.app") { LoginItem.set(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.ui.welcomeShown = true
                self?.openPanel()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.closePanel(); self?.findNotch() }
        }
    }

    private func makePanel(level: NSWindow.Level) -> KeyPanel {
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = level
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false
        return p
    }

    /// The built-in display's camera housing. Without one (lid closed, external display only),
    /// a notch-sized spot at the top centre of the main screen stands in for it.
    private func findNotch() {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            let h = s.safeAreaInsets.top
            let local = l.minX < s.frame.minX || l.maxX <= s.frame.width && s.frame.minX != 0
            let x0 = local ? s.frame.minX + l.maxX : l.maxX
            let x1 = local ? s.frame.minX + r.minX : r.minX
            screen = s
            notch = NSRect(x: x0, y: s.frame.maxY - h, width: x1 - x0, height: h)
        } else if let s = NSScreen.main {
            let h = max(NSStatusBar.system.thickness, 24)
            screen = s
            notch = NSRect(x: s.frame.midX - 92, y: s.frame.maxY - h, width: 184, height: h)
        }
        ui.notchWidth = notch.width
        ui.height = notch.height
    }

    // MARK: the notch

    private func watchPointer() {
        let p = NSEvent.mouseLocation
        if !ui.expanded {
            let hot = NSRect(x: notch.minX - 8, y: notch.minY - 2, width: notch.width + 16, height: notch.height + 8)
            if hot.contains(p) { dwell += 1; if dwell >= 3 { expand() } } else { dwell = 0 }
        } else if !ui.panelShown {
            if cap.frame.insetBy(dx: -16, dy: -16).contains(p) { away = 0 } else { away += 1; if away >= 8 { collapse() } }
        }
    }

    private func expand() {
        guard !ui.expanded else { return }
        dwell = 0; away = 0
        let w = ui.windowWidth
        cap.setFrame(NSRect(x: notch.midX - w / 2, y: notch.maxY - notch.height, width: w, height: notch.height), display: true)
        cap.orderFrontRegardless()
        // Let the cap draw once at notch size, then spring it open: a little overshoot is the "click".
        DispatchQueue.main.async { [self] in
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            if store.config.clickSound { click?.volume = 0.25; click?.stop(); click?.play() }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.58)) { ui.expanded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { self.ui.showTimes = true }
            }
        }
    }

    private func collapse() {
        guard ui.expanded, !ui.panelShown else { return }
        away = 0
        withAnimation(.easeIn(duration: 0.1)) { ui.showTimes = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { self.ui.expanded = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.ui.expanded { self.cap.orderOut(nil) }
        }
    }

    // MARK: the panel

    fileprivate func updateFound(_ version: String?) { ui.updateReady = version }

    private func togglePanel() { ui.panelShown ? closePanel() : openPanel() }

    private func openPanel(settings: Bool = false) {
        if settings { ui.settingsShown = true }
        guard !ui.panelShown else { return }
        if !ui.expanded { expand() }
        store.reload()
        store.backToNow()
        store.flash = nil
        layoutPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ui.panelShown = true }
        }
    }

    private func closePanel() {
        guard ui.panelShown else { return }
        withAnimation(.easeIn(duration: 0.14)) { ui.panelShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [self] in
            guard !ui.panelShown else { return }
            panel.orderOut(nil)
            ui.settingsShown = false
            if ui.welcomeShown { ui.welcomeShown = false; store.markWelcomed() }
            store.backToNow()
            if !cap.frame.insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation) { collapse() }
        }
    }

    /// Hangs the ribbon from the top edge, centred under the notch and kept on screen.
    private func layoutPanel() {
        let size = panelHost.fittingSize
        guard let s = screen else { return }
        var x = notch.midX - size.width / 2
        x = max(s.frame.minX + 8, min(x, s.frame.maxX - size.width - 8))
        panel.setFrame(NSRect(x: x, y: s.frame.maxY - notch.height - size.height, width: size.width, height: size.height), display: true)
    }

    /// Clicking an hour proposes it as an hour-long block; pressing on the block and dragging
    /// slides it in 5-minute steps. Done here rather than with SwiftUI gestures so the first click
    /// counts in a panel that never activates the app.
    private func gridMouse(_ e: NSEvent) -> NSEvent? {
        guard e.window === panel, ui.panelShown, !ui.settingsShown, !ui.welcomeShown, store.timeQuery == nil,
              let view = panel.contentView else { return e }
        let x = e.locationInWindow.x
        let fromTop = view.bounds.height - e.locationInWindow.y
        let rowsHeight = Metrics.rowsHeight(store.rows.map(store.isHidden))
        let onGrid = x >= Metrics.gridX && x < Metrics.gridX + Metrics.gridWidth
            && fromTop >= Metrics.top - 8 && fromTop <= Metrics.top + rowsHeight + 4
        switch e.type {
        case .leftMouseDown:
            guard onGrid else { drag = nil; return e }
            let hours = Double((x - Metrics.gridX) / Metrics.pitch) + store.scroll   // home hours from dayStart
            let start = store.proposal.map { $0.timeIntervalSince(store.dayStart) / 3600 }
            if let s = start, hours >= s - 0.1, hours <= s + Double(store.duration) / 60 + 0.1 {
                drag = (x, store.proposal!)                 // pressed on the block: drag it
            } else {
                store.propose(col: store.column(atX: Double(x - Metrics.gridX), pitch: Double(Metrics.pitch)))   // pressed elsewhere: the block starts at that hour
                drag = (x, store.proposal!)
            }
            return nil
        case .leftMouseDragged:
            guard let d = drag else { return e }
            let minutes = Double((x - d.x) / Metrics.pitch) * 60
            store.place(d.from.addingTimeInterval(minutes * 60))
            return nil
        default:
            guard drag != nil else { return e }
            drag = nil
            return nil
        }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if ui.welcomeShown {
            if Int(e.keyCode) == kVK_Escape { closePanel(); return true }
            return false
        }
        // Typing a time: keys belong to the field; esc puts the earlier time back.
        if store.timeQuery != nil {
            if Int(e.keyCode) == kVK_Escape { store.finishTyping(keep: false); return true }
            return false
        }
        // In the settings the keys belong to the text fields; esc goes back to the ribbon.
        if ui.settingsShown {
            if Int(e.keyCode) == kVK_Escape { ui.settingsShown = false; return true }
            if mods.contains(.command) && e.charactersIgnoringModifiers == "w" { closePanel(); return true }
            return false
        }
        if mods.contains(.command) {
            if e.charactersIgnoringModifiers == "w" { closePanel(); return true }
            if e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return true }
            if e.charactersIgnoringModifiers == "c" { copyText(); return true }
            return false
        }
        switch Int(e.keyCode) {
        case kVK_Escape: closePanel(); return true
        case kVK_LeftArrow: store.step(minutes: mods.contains(.shift) ? -60 : -5); return true
        case kVK_RightArrow: store.step(minutes: mods.contains(.shift) ? 60 : 5); return true
        default: break
        }
        // A digit starts a typed time ("6:15 india"), with that digit already in the field.
        if let ch = e.characters, ch.count == 1, ch.first!.isNumber {
            store.startTyping(ch)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                (self?.panel.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
            }
            return true
        }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "h": store.step(minutes: -60)
        case "l": store.step(minutes: 60)
        case "f": store.jumpToFairest()
        case "n": store.backToNow()
        case "t": store.format = store.format.next; flash(nil); layoutPanel()
        case "p", "y": copyPicture()
        case "c": copyText()
        case "s": ui.settingsShown = true
        case "[": store.changeDay(by: -1)
        case "]": store.changeDay(by: 1)
        case "d": store.cycleDuration()
        case "u": ui.onUpdates()
        default: return false
        }
        return true
    }

    private func flash(_ text: String?) {
        store.flash = text
        guard text != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.store.flash == text { self?.store.flash = nil }
        }
    }

    // MARK: copying

    private func copyText() {
        setClipboard(store.asText(at: store.focus))
        flash("Copied the times as text — paste them into a message")
    }

    private func copyInvite() {
        let at = store.proposal ?? store.instant(store.fairestCol)
        setClipboard(store.emailText(from: at))
        flash("Copied \(store.range(from: at, store.homeRow)) for \(store.visiblePlaces.count) places — paste it into the email")
    }

    private func setClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func copyPicture() {
        let dark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let png = render(RibbonPanel(store: store, ui: ui, solid: true, hints: false)
            .environment(\.colorScheme, dark ? .dark : .light)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        flash("Copied as a picture — paste it to the people in the meeting")
    }

    private func render<V: View>(_ view: V) -> Data? {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

/// Gentle reminders (Sparkle's term): Halfpast has no Dock icon or window of its own, so an update
/// alert found in the background could open unseen behind other apps. Instead a quiet arrow
/// appears on the notch and an Update button in the ribbon; the alert opens when he asks.
extension AppDelegate: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.updateFound(version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.updateFound(nil) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.updateFound(nil) }
    }
}
