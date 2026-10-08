import AppKit
import CoreLocation
import CoreWLAN

/// Drives Engine.offTrustedWiFi: with auto-hide on, alerts hide details unless we're on a trusted Wi-Fi network.
@MainActor final class WiFiWatcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WiFiWatcher()

    @Published var autoHide = false {
        didSet {
            UserDefaults.standard.set(autoHide, forKey: Self.autoHideKey)
            // Only ask for Location when the user opts in, never at launch.
            if autoHide, location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
            refresh()
        }
    }
    @Published private(set) var trusted: [String] = []
    /// Current network name; nil when off Wi-Fi, auto-hide is off, or we lack Location access.
    @Published private(set) var ssid: String?
    @Published private(set) var status: CLAuthorizationStatus

    /// macOS only reports .authorizedAlways (.authorized is the same value); there's no when-in-use state.
    var authorized: Bool { status == .authorizedAlways }
    var denied: Bool { status == .denied || status == .restricted }

    private static let autoHideKey = "wifiAutoHide"
    private static let trustedKey = "trustedSSIDs"
    private let location = CLLocationManager()
    private var timer: Timer?

    override init() {
        status = location.authorizationStatus
        super.init()
        trusted = UserDefaults.standard.stringArray(forKey: Self.trustedKey) ?? []
        autoHide = UserDefaults.standard.bool(forKey: Self.autoHideKey)  // didSet doesn't run in init
        location.delegate = self
    }

    func start() {
        guard timer == nil else { return }
        // ponytail: polling every 10s; switch to CWEventDelegate ssidDidChange if the lag matters.
        let t = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { WiFiWatcher.shared.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func trustCurrent() {
        guard let ssid, !trusted.contains(ssid) else { return }
        trusted.append(ssid)
        saveTrusted()
    }

    func remove(_ name: String) {
        trusted.removeAll { $0 == name }
        saveTrusted()
    }

    private func saveTrusted() {
        UserDefaults.standard.set(trusted, forKey: Self.trustedKey)
        refresh()
    }

    func refresh() {
        // Without Location access macOS returns nil for the SSID, same as being off Wi-Fi.
        let now = autoHide && authorized ? CWWiFiClient.shared().interface()?.ssid() : nil
        if now != ssid { ssid = now }
        let hide = Self.hidden(autoHide: autoHide, ssid: ssid, trusted: trusted)
        if hide != Engine.shared.offTrustedWiFi { Engine.shared.offTrustedWiFi = hide }
    }

    /// An unknown network (off Wi-Fi, or Location denied so we can't read the name) counts as untrusted:
    /// failing open would leak event details exactly when the user asked us not to. Settings shows a
    /// warning when Location is denied, so "always hidden" never happens silently.
    nonisolated static func hidden(autoHide: Bool, ssid: String?, trusted: [String]) -> Bool {
        guard autoHide else { return false }
        guard let ssid else { return true }
        return !trusted.contains(ssid)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Delivered on main: the manager was created there.
        MainActor.assumeIsolated {
            status = manager.authorizationStatus
            refresh()
        }
    }
}
