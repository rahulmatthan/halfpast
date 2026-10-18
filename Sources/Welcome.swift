import ServiceManagement
import SwiftUI

/// Shown once, in the glass panel, the first time Halfpast runs: there is no menu bar icon, so
/// it says where the app lives and how to use it.
struct WelcomeView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    var onDone: (_ setUp: Bool) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        PanelChrome {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Halfpast").font(hanken(30, .semibold))
                    Text("The time elsewhere, tucked into your notch.").font(hanken(16)).foregroundStyle(p.mist)
                }
                step("cursorarrow.motionlines", "Rest your pointer on the notch",
                     "Two of your places appear either side of the camera. Move away and they fold back.", p)
                step("rectangle.grid.1x2", "Click it, or press ⌃⌥T",
                     "Every place as a 24-hour strip, lined up on the same moment, with the fairest hour for a meeting outlined.", p)
                step("envelope", "Propose a time",
                     "Click an hour, nudge it five minutes at a time, or type “7:30am NY tue”. Then copy it for an email.", p)
                Text("Right-click the notch for Places & appearance. Halfpast opens when you log in; you can switch that off there.")
                    .font(hanken(13)).foregroundStyle(p.mist)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Spacer()
                    Button { onDone(true) } label: {
                        Text("Choose my places").font(hanken(14, .semibold)).foregroundStyle(p.text)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(p.chip, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.chipBorder))
                    }
                    .buttonStyle(.plain)
                    Button { onDone(false) } label: {
                        Text("Got it").font(hanken(14, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            .background(p.button, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(32)
            .frame(width: 620, alignment: .leading)
        }
    }

    private func step(_ icon: String, _ title: String, _ detail: String, _ p: Palette) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(p.fair)
                .frame(width: 30, height: 30)
                .background(p.chip, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(hanken(16, .semibold))
                Text(detail).font(hanken(14)).foregroundStyle(p.mist).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Opening at login, through macOS's own login items (System Settings › General › Login Items).
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}
