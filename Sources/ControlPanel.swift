import SwiftUI

/// The right-click popover: global levels, then one collapsible section per panel.
struct ControlPanel: View {
    @ObservedObject var lights: LumeController
    @ObservedObject var app: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lume Cube").font(.headline)
                    Text("\(lights.connectedCount)/\(LumeProtocol.expectedPanels) panels connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { lights.anyOn }, set: { app.setPower($0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("All panels")
            }

            Levels(brightness: Binding(get: { lights.globalBrightness }, set: { lights.setGlobalBrightness($0) }),
                   kelvin: Binding(get: { lights.globalKelvin }, set: { lights.setGlobalKelvin($0) }))

            if !lights.panelStates.isEmpty {
                Divider()
                ForEach(lights.panelStates) { PanelRow(panel: $0, lights: lights) }
            }

            Divider()
            Toggle("Turn On With Camera", isOn: Binding(get: { app.autoMode }, set: { _ in app.toggleAuto() }))
            Toggle("Launch at Login", isOn: Binding(get: { app.launchAtLogin }, set: { _ in app.toggleLaunchAtLogin() }))
            HStack {
                Button("Reconnect") { lights.reconnect() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct PanelRow: View {
    let panel: PanelState
    let lights: LumeController

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("On", isOn: Binding(get: { panel.isOn }, set: { lights.setPower($0, panel: panel.id) }))
                    .toggleStyle(.switch)
                Levels(brightness: Binding(get: { panel.brightness }, set: { lights.setBrightness($0, panel: panel.id) }),
                       kelvin: Binding(get: { panel.kelvin }, set: { lights.setKelvin($0, panel: panel.id) }))
                TextField(panel.id, text: Binding(get: { lights.label(for: panel.id) ?? "" },
                                                  set: { lights.rename(panel.id, to: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .help("Name shown in LumeToggle only. Leave empty to use \(panel.id).")
            }
            .padding(.top, 6)
            .disabled(!panel.connected)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(panel.connected ? (panel.isOn ? Color.yellow : Color.green) : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(panel.label)
                if !panel.connected { Text("connecting…").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct Levels: View {
    @Binding var brightness: Int
    @Binding var kelvin: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("sun.max", "\(brightness)%") {
                Slider(value: double($brightness, step: 1),
                       in: Double(LumeProtocol.brightnessRange.lowerBound)...Double(LumeProtocol.brightnessRange.upperBound))
            }
            row("thermometer.medium", "\(kelvin)K") {
                Slider(value: double($kelvin, step: LumeProtocol.kelvinStep),
                       in: Double(LumeProtocol.kelvinRange.lowerBound)...Double(LumeProtocol.kelvinRange.upperBound))
            }
        }
    }

    private func row(_ symbol: String, _ value: String, @ViewBuilder slider: () -> some View) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            slider()
            Text(value).monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }

    /// Snaps in the binding rather than via `Slider(step:)`, which on macOS draws a tick
    /// mark for every step.
    private func double(_ b: Binding<Int>, step: Int) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) },
                set: { b.wrappedValue = Int(($0 / Double(step)).rounded()) * step })
    }
}
