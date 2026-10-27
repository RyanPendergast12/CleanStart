import CFNetwork
import Foundation
import Network

/// Observes the connection type and whether a VPN appears to be active.
/// Only the interface *type* is used; SSIDs and IP addresses are never read.
@MainActor
final class NetworkStatusService: ObservableObject {
    enum Kind: String {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"
        case wired = "Wired"
        case other = "Other network"
        case offline = "No connection"
    }

    @Published private(set) var kind: Kind = .other
    @Published private(set) var vpnLikelyActive = false
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.update(path) }
        }
        monitor.start(queue: DispatchQueue(label: "cleanstart.network-path"))
    }

    deinit {
        monitor.cancel()
    }

    var description: String { kind.rawValue }

    private func update(_ path: NWPath) {
        if path.status != .satisfied {
            kind = .offline
        } else if path.usesInterfaceType(.wifi) {
            kind = .wifi
        } else if path.usesInterfaceType(.cellular) {
            kind = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            kind = .wired
        } else {
            kind = .other
        }
        isExpensive = path.isExpensive
        vpnLikelyActive = Self.detectVPN()
    }

    /// Heuristic: VPN tunnels appear as scoped utun/ipsec/ppp interfaces in the
    /// system proxy settings. It can't tell a work VPN from a personal one.
    static func detectVPN() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any] else { return false }
        let prefixes = ["utun", "ipsec", "ppp", "tun", "tap"]
        return scoped.keys.contains { key in prefixes.contains { key.hasPrefix($0) } }
    }
}
