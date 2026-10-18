import AppKit
import SwiftUI

/// Animation state shared by the notch cap and the panel.
@MainActor
final class NotchUI: ObservableObject {
    @Published var expanded = false     // the cap has grown out of the notch
    @Published var showTimes = false    // the two times have popped in
    @Published var panelShown = false   // the glass ribbon has dropped down
    @Published var settingsShown = false // places & appearance instead of the ribbon
    @Published var welcomeShown = false  // the first-run welcome instead of the ribbon
    var notchWidth: CGFloat = 185
    var height: CGFloat = 32
    let ear: CGFloat = 92               // how far the cap grows either side of the camera
    let shoulder: CGFloat = 7           // the outward flare where the cap meets the top edge

    var windowWidth: CGFloat { notchWidth + 2 * ear + 2 * shoulder }

    var onTap: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
}

/// The notch outline: flared shoulders at the top edge so the cap reads as part of the bezel,
/// rounded corners at the bottom.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, radius) }
        set { shoulder = newValue.first; radius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let s = shoulder, rad = min(radius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + s, y: r.minY + s), control: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + s + rad, y: r.maxY), control: CGPoint(x: r.minX + s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s - rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - s, y: r.maxY - rad), control: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - s, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// The black cap: at rest it is exactly the notch; on hover it springs wider and the two
/// places pop in either side of the camera.
struct NotchView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI

    var body: some View {
        let s = ui.expanded ? ui.shoulder : 0
        let body = ui.expanded ? ui.notchWidth + 2 * ui.ear : ui.notchWidth
        let pair = store.notchRows
        ZStack(alignment: .top) {
            NotchShape(shoulder: s, radius: ui.expanded ? 14 : 10)
                .fill(.black)
                .frame(width: body + 2 * s, height: ui.height)
            HStack(spacing: 0) {
                if pair.count == 2 {
                    ear(pair[0], leading: true)
                    Spacer(minLength: ui.notchWidth)
                    ear(pair[1], leading: false)
                }
            }
            .padding(.horizontal, s + 14)
            .frame(width: body + 2 * s, height: ui.height)
            .opacity(ui.showTimes ? 1 : 0)
            .scaleEffect(ui.showTimes ? 1 : 0.55)
            .blur(radius: ui.showTimes ? 0 : 3)
        }
        .frame(width: ui.windowWidth, height: ui.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { ui.onTap() }
        .contextMenu {
            Button("Places & appearance…") { ui.onSettings() }
            Divider()
            Button("Quit Halfpast") { ui.onQuit() }
        }
    }

    private func ear(_ row: Row, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if leading { mark(row) }
            if leading { Text(row.short).font(hanken(12)).foregroundStyle(Trilegal.mist) }
            Text(store.time(store.now, row).replacingOccurrences(of: " AM", with: "a").replacingOccurrences(of: " PM", with: "p"))
                .font(hanken(13, .semibold))
                .foregroundStyle(.white)
            if !leading { Text(row.short).font(hanken(12)).foregroundStyle(Trilegal.mist) }
            if !leading { mark(row) }
        }
        .fixedSize()
    }

    /// Teal dot at work, orange dot awake, a moon asleep.
    @ViewBuilder private func mark(_ row: Row) -> some View {
        switch row.phase(at: store.now) {
        case .work: Circle().fill(Trilegal.teal).frame(width: 7, height: 7)
        case .awake: Circle().fill(Trilegal.orange).frame(width: 7, height: 7)
        case .asleep: Image(systemName: "moon.fill").font(.system(size: 9)).foregroundStyle(Trilegal.mist)
        }
    }
}
