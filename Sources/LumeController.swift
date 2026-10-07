import Combine
import CoreBluetooth
import Foundation

// Recovered from the Lumecube Android app (v2.0.2). Panel Pro = Telink classic mesh.
enum LumeProtocol {
    static let service = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D1910")
    static let command = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D1912")
    static let pair    = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D1914")
    /// The app's hardcoded mesh password, then the Telink factory default.
    static let passwords = ["4rfv5tgb", "123"]
    static let opOnOff: UInt8 = 0xD0      // params: [1,0,0] on, [0,0,0] off
    static let opBrightness: UInt8 = 0xD2 // params: [bri]
    static let opColor: UInt8 = 0xE2      // params: [5, temp, bri] for colour temperature
    static let expectedPanels = 2

    static let brightnessRange = 5...100
    /// The app's slider: 0…100 on the wire spans 3000–5700 K, warm to cool.
    static let kelvinRange = 3000...5700
    static let kelvinStep = 100

    static func tempByte(_ kelvin: Int) -> UInt8 {
        let k = min(max(kelvin, kelvinRange.lowerBound), kelvinRange.upperBound)
        let span = Double(kelvinRange.upperBound - kelvinRange.lowerBound)
        return UInt8((Double(k - kelvinRange.lowerBound) * 100 / span).rounded())
    }

    static func briByte(_ brightness: Int) -> UInt8 {
        UInt8(min(max(brightness, brightnessRange.lowerBound), brightnessRange.upperBound))
    }
}

/// Per-panel settings, persisted by mesh name. nil levels mean "never set from this app",
/// so the panel keeps whatever it already has.
struct PanelSettings: Codable {
    var label: String?
    var brightness: Int?
    var kelvin: Int?
}

/// Snapshot of one panel for the UI.
struct PanelState: Identifiable {
    let id: String            // mesh name
    let label: String
    let connected: Bool
    let isOn: Bool
    let brightness: Int
    let kelvin: Int
}

private final class Panel {
    let peripheral: CBPeripheral
    let name: String          // advertised name == mesh name
    let mac4: [UInt8]         // low 4 MAC bytes from manufacturer data (macOS hides the MAC)
    var pairChar: CBCharacteristic?
    var cmdChar: CBCharacteristic?
    var randm: [UInt8] = []
    var passIndex = 0
    var sessionKey: [UInt8]?
    var seq = UInt32.random(in: 1..<0xF0_0000)
    var ready: Bool { sessionKey != nil && cmdChar != nil }

    init(peripheral: CBPeripheral, name: String, mac4: [UInt8]) {
        self.peripheral = peripheral; self.name = name; self.mac4 = mac4
    }
}

final class LumeController: NSObject, ObservableObject {
    var onStatusChange: (() -> Void)?
    var connectedCount: Int { panels.values.filter(\.ready).count }
    /// True if any known panel is (or will be, once connected) on.
    var anyOn: Bool { panels.values.contains { power[$0.name] ?? desiredPower ?? false } || (panels.isEmpty && desiredPower == true) }

    @Published private(set) var panelStates: [PanelState] = []
    @Published private(set) var globalBrightness: Int
    @Published private(set) var globalKelvin: Int

    private var central: CBCentralManager!
    private var panels: [UUID: Panel] = [:]
    private var rejected: Set<UUID> = []
    private var desiredPower: Bool?
    /// Per-panel power, by mesh name. Survives reconnects; not persisted.
    private var power: [String: Bool] = [:]
    private var settings: [String: PanelSettings]
    private let dump = CommandLine.arguments.contains("--dump")

    // Slider drags coalesce into one write per panel per tick rather than flooding the link.
    private enum Change { case brightness, kelvin }
    private var pending: [String: Set<Change>] = [:]
    private var flushScheduled = false
    private let flushInterval: TimeInterval = 0.06

    private static let settingsKey = "panelSettings"

    override init() {
        let d = UserDefaults.standard
        settings = (d.data(forKey: Self.settingsKey))
            .flatMap { try? JSONDecoder().decode([String: PanelSettings].self, from: $0) } ?? [:]
        globalBrightness = d.object(forKey: "globalBrightness") as? Int ?? 100
        globalKelvin = d.object(forKey: "globalKelvin") as? Int ?? 5600
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Control

    func setPower(_ on: Bool) {
        desiredPower = on
        if connectedCount < LumeProtocol.expectedPanels { startScan() }
        for panel in panels.values {
            power[panel.name] = on
            sendPower(on, to: panel)
        }
        publish()
    }

    func setPower(_ on: Bool, panel name: String) {
        power[name] = on
        if let panel = panel(named: name) { sendPower(on, to: panel) }
        publish()
    }

    func setBrightness(_ value: Int, panel name: String) {
        guard settings[name, default: .init()].brightness != value else { return }
        settings[name, default: .init()].brightness = value
        queue(name, .brightness)
        saveSettings()
    }

    func setKelvin(_ value: Int, panel name: String) {
        guard settings[name, default: .init()].kelvin != value else { return }
        settings[name, default: .init()].kelvin = value
        // The temperature command carries brightness too, so pin it down now.
        if settings[name]?.brightness == nil { settings[name]?.brightness = globalBrightness }
        queue(name, .kelvin)
        saveSettings()
    }

    /// Overrides every panel's individual brightness.
    func setGlobalBrightness(_ value: Int) {
        guard value != globalBrightness else { return }
        globalBrightness = value
        UserDefaults.standard.set(value, forKey: "globalBrightness")
        for name in allNames {
            settings[name, default: .init()].brightness = value
            queue(name, .brightness)
        }
        saveSettings()
    }

    /// Overrides every panel's individual colour temperature.
    func setGlobalKelvin(_ value: Int) {
        guard value != globalKelvin else { return }
        globalKelvin = value
        UserDefaults.standard.set(value, forKey: "globalKelvin")
        for name in allNames {
            settings[name, default: .init()].kelvin = value
            if settings[name]?.brightness == nil { settings[name]?.brightness = globalBrightness }
            queue(name, .kelvin)
        }
        saveSettings()
    }

    /// In-app only; the panel's mesh name is untouched. Empty reverts to the mesh name.
    func rename(_ name: String, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        settings[name, default: .init()].label = trimmed.isEmpty ? nil : label
        saveSettings()
    }

    func label(for name: String) -> String? { settings[name]?.label }

    func reconnect() {
        let old = panels.values.map(\.peripheral)
        panels.removeAll()
        rejected.removeAll()
        old.forEach { central.cancelPeripheralConnection($0) }
        publish()
        startScan()
    }

    // MARK: - Internals

    private var allNames: Set<String> { Set(settings.keys).union(panels.values.map(\.name)) }

    private func panel(named name: String) -> Panel? { panels.values.first { $0.name == name } }

    private func publish() {
        panelStates = panels.values.sorted { $0.name < $1.name }.map { p in
            let s = settings[p.name]
            return PanelState(id: p.name, label: s?.label ?? p.name, connected: p.ready,
                              isOn: power[p.name] ?? desiredPower ?? false,
                              brightness: s?.brightness ?? globalBrightness,
                              kelvin: s?.kelvin ?? globalKelvin)
        }
        onStatusChange?()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        publish()
    }

    private func queue(_ name: String, _ change: Change) {
        pending[name, default: []].insert(change)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval) { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        let work = pending
        pending = [:]
        for (name, changes) in work {
            if let panel = panel(named: name) { sendLevels(changes, to: panel) }
        }
    }

    private func startScan() {
        guard central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func login(_ panel: Panel) {
        guard let pair = panel.pairChar else { return }
        panel.randm = (0..<8).map { _ in UInt8.random(in: 0...255) }
        let pkt = Telink.loginPacket(name: panel.name, pass: LumeProtocol.passwords[panel.passIndex],
                                     randm: panel.randm)
        panel.peripheral.writeValue(Data(pkt), for: pair, type: .withResponse)
    }

    private func sendPower(_ on: Bool, to panel: Panel) {
        send(LumeProtocol.opOnOff, [on ? 1 : 0, 0, 0], to: panel)
    }

    /// Temperature already includes brightness, so it covers both when both changed.
    private func sendLevels(_ changes: Set<Change>, to panel: Panel) {
        let s = settings[panel.name] ?? .init()
        let bri = LumeProtocol.briByte(s.brightness ?? globalBrightness)
        if changes.contains(.kelvin), let k = s.kelvin {
            send(LumeProtocol.opColor, [5, LumeProtocol.tempByte(k), bri], to: panel)
        } else if changes.contains(.brightness), s.brightness != nil {
            send(LumeProtocol.opBrightness, [bri], to: panel)
        }
    }

    private func send(_ opcode: UInt8, _ params: [UInt8], to panel: Panel) {
        guard let key = panel.sessionKey, let cmd = panel.cmdChar else { return }
        panel.seq = (panel.seq &+ 1) & 0xFF_FFFF
        let pkt = Telink.commandPacket(key: key, mac4: panel.mac4, seq: panel.seq,
                                       opcode: opcode, params: params)
        panel.peripheral.writeValue(Data(pkt), for: cmd, type: .withoutResponse)
    }

    /// Bring a freshly logged-in panel in line with the app: levels first, then power,
    /// so a level change can't leave a panel lit that should be off.
    private func sync(_ panel: Panel) {
        let s = settings[panel.name] ?? .init()
        var changes: Set<Change> = []
        if s.brightness != nil { changes.insert(.brightness) }
        if s.kelvin != nil { changes.insert(.kelvin) }
        sendLevels(changes, to: panel)
        guard let on = power[panel.name] ?? desiredPower else { return }
        power[panel.name] = on
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.sendPower(self.power[panel.name] ?? on, to: panel)
        }
    }
}

extension LumeController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { startScan() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let mfg = [UInt8](ad[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data())
        let name = ad[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        if dump { print("seen  \(name.isEmpty ? "?" : name)  \(p.identifier)  rssi=\(rssi)  mfg=\(Telink.hex(mfg))") }

        // Telink vendor 0x0211 (bytes 11 02); MAC low 4 bytes at offset 4.
        guard mfg.count >= 8, mfg[0] == 0x11, mfg[1] == 0x02, !name.isEmpty,
              panels[p.identifier] == nil, !rejected.contains(p.identifier) else { return }
        let panel = Panel(peripheral: p, name: name, mac4: Array(mfg[4..<8]))
        panels[p.identifier] = panel
        p.delegate = self
        print("found \(name)  mac…\(Telink.hex(Array(panel.mac4.reversed())))")
        publish()
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([LumeProtocol.service])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard let panel = panels[p.identifier] else { return }
        panel.sessionKey = nil
        publish()
        c.connect(p)  // auto-reconnect; re-login happens after service discovery
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        panels[p.identifier] = nil
        publish()
    }
}

extension LumeController: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == LumeProtocol.service {
            p.discoverCharacteristics([LumeProtocol.command, LumeProtocol.pair], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let panel = panels[p.identifier] else { return }
        for ch in s.characteristics ?? [] {
            if ch.uuid == LumeProtocol.command { panel.cmdChar = ch }
            if ch.uuid == LumeProtocol.pair { panel.pairChar = ch }
        }
        login(panel)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == LumeProtocol.pair else { return }
        if let error { print("login write failed: \(error.localizedDescription)") }
        p.readValue(for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == LumeProtocol.pair, let panel = panels[p.identifier] else { return }
        let resp = [UInt8](ch.value ?? Data())
        let pass = LumeProtocol.passwords[panel.passIndex]

        if let sk = Telink.sessionKey(name: panel.name, pass: pass, randm: panel.randm, response: resp) {
            panel.sessionKey = sk
            print("logged in to \(panel.name)")
            sync(panel)   // late joiners pick up the app's state
            publish()
            if connectedCount >= LumeProtocol.expectedPanels { central.stopScan() }
        } else if panel.passIndex + 1 < LumeProtocol.passwords.count {
            panel.passIndex += 1
            login(panel)
        } else {
            print("login failed for \(panel.name) (resp \(Telink.hex(resp))); ignoring it")
            rejected.insert(p.identifier)
            panels[p.identifier] = nil
            central.cancelPeripheralConnection(p)
            publish()
        }
    }
}
