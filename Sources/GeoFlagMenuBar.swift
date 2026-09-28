import AppKit
import Network

// MARK: - Networking

struct GeoInfo {
    var ip: String = "…"
    var country: String = "…"
    var flag: String = "🏳"
    var city: String = ""
    var changed: Bool = false
    var isFallback: Bool = false
}

final class GeoFetcher {
    static let shared = GeoFetcher()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    func fetch(completion: @escaping (GeoInfo) -> Void) {
        // Several endpoints, first success wins; if all fail -> offline mark.
        let endpoints: [String] = [
            "https://ipinfo.io/json",
            "https://ifconfig.co/json",
            "https://api.myip.com",
        ]
        var results: [GeoInfo] = []
        results.reserveCapacity(endpoints.count)
        let group = DispatchGroup()
        let q = DispatchQueue(label: "geo.merge")
        for (idx, ep) in endpoints.enumerated() {
            group.enter()
            session.dataTask(with: URL(string: ep)!) { data, _, error in
                defer { group.leave() }
                guard error == nil, let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                let ip = (obj["ip"] as? String)
                    ?? (obj["ip_addr"] as? String)
                    ?? "?"
                // Both ISO-2 ("RU") and language-style ("en") variants handled.
                var country = (obj["country"] as? String)
                    ?? (obj["country_iso"] as? String)
                    ?? "?"
                let city = (obj["city"] as? String) ?? ""
                // api.myip.com returns full name; use "country_iso" if present else map later.
                if country.count > 2, let iso = obj["country_iso"] as? String { country = iso }
                if country.count != 2 { return }
                let info = GeoInfo(ip: ip, country: country, flag: Self.flagEmoji(country), city: city,
                                   changed: false, isFallback: false)
                q.sync { results.append(info) }
                // Prefer the earlier endpoint when it responds.
                if idx == 0 {
                    q.sync { results.sort { $0.ip <= $1.ip } }
                }
            }.resume()
        }
        group.notify(queue: .main) {
            if let first = results.first {
                completion(first)
            } else {
                var off = GeoInfo()
                off.ip = "оффлайн"
                off.country = "--"
                off.flag = "🚫"
                off.isFallback = true
                completion(off)
            }
        }
    }

    static func flagEmoji(_ code: String) -> String {
        guard code.count == 2, code.allSatisfy({ $0.isLetter && $0.isASCII }) else { return "🏳" }
        return code.uppercased().unicodeScalars.reduce(into: "") { acc, c in
            if let scalar = Unicode.Scalar(0x1F1E6 + (c.value - 65)) { acc.unicodeScalars.append(scalar) }
        }
    }
}

// MARK: - Connectivity observation (instant, via NWPathMonitor)

final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()
    private let monitor = NWPathMonitor()
    private(set) var isOnline: Bool? = nil
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = path.status == .satisfied
            guard let prev = self.isOnline else {
                // Initial callback: just record state; UI handles its own first check.
                self.isOnline = online
                if !online { DispatchQueue.main.async { self.onChange?(false) } }
                return
            }
            if online != prev {
                self.isOnline = online
                DispatchQueue.main.async { self.onChange?(online) }
            } else if online {
                // Same state, but interface changed (Wi-Fi <-> Ethernet) — still trigger checks.
                DispatchQueue.main.async { self.onChange?(true) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.path.monitor"))
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    let ipItem = NSMenuItem(title: "IP: …", action: nil, keyEquivalent: "")
    let countryItem = NSMenuItem(title: "Страна: …", action: nil, keyEquivalent: "")
    let cityItem = NSMenuItem(title: "Город: —", action: nil, keyEquivalent: "")
    let refreshedItem = NSMenuItem(title: "Обновлено: —", action: nil, keyEquivalent: "")
    let checkNowItem = NSMenuItem(title: "Проверить сейчас", action: #selector(checkNow), keyEquivalent: "r")
    let quitItem = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    var lastSignature: (ip: String, country: String) = ("", "")
    var lastRefresh: Date?
    var timer: Timer?
    var isOffline = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "⏳"
            btn.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        [ipItem, countryItem, cityItem, refreshedItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())
        checkNowItem.target = self
        menu.addItem(checkNowItem)
        menu.addItem(.separator())
        quitItem.target = nil
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu

        // Poll + react to interface changes (VPN up/down, Wi-Fi <-> Ethernet, sleep wake).
        DistributedNotificationCenter.default()
            .addObserver(self, selector: #selector(scheduleCheck), name: NSNotification.Name("com.apple.system.config.network_change"), object: nil)
        DistributedNotificationCenter.default()
            .addObserver(self, selector: #selector(scheduleCheck), name: .NSSystemTimeZoneDidChange, object: nil)
        DistributedNotificationCenter.default()
            .addObserver(self, selector: #selector(scheduleCheck), name: .NSSystemClockDidChange, object: nil)
        NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(scheduleCheck), name: NSWorkspace.didWakeNotification, object: nil)

        // Instant connectivity state: flips the badge to 🚫 the moment the path goes down,
        // and back to the last known flag when it returns.
        ConnectivityMonitor.shared.onChange = { [weak self] online in
            guard let self = self else { return }
            self.isOffline = !online
            if let btn = self.statusItem.button {
                btn.title = online ? "⏳" : "🚫"
            }
            refreshedItem.title = online ? "Обновлено: — (сеть появилась)" : "Нет сети"
            if online { self.scheduleCheck() }
        }
        ConnectivityMonitor.shared.start()

        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.scheduleCheck() }
    }

    @objc func scheduleCheck() {
        // Don't hit the network while there's no connectivity; NWPathMonitor will wake us on recovery.
        guard !isOffline else { return }
        // Debounce rapid bursts of network_change notifications.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(doCheck), object: nil)
        perform(#selector(doCheck), with: nil, afterDelay: 1.5)
    }

    @objc func doCheck() { GeoFetcher.shared.fetch { [weak self] info in self?.apply(info) } }

    @objc func checkNow() { scheduleCheck() }

    func apply(_ info: GeoInfo) {
        lastRefresh = Date()
        let changed = (info.ip, info.country) != lastSignature
        if changed { lastSignature = (info.ip, info.country) }
        if let btn = statusItem.button {
            btn.title = info.changed ? "\(info.flag) " : "\(info.flag)"
            btn.title = "\(info.flag)"
        }
        ipItem.title = "IP: \(info.ip)"
        countryItem.title = "Страна: \(info.country) \(info.flag)"
        cityItem.title = "Город: \(info.city.isEmpty ? "—" : info.city)"
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        refreshedItem.title = "Обновлено: \(f.string(from: lastRefresh!))" + (changed ? "  (изменилось!)" : "")
        // Simple attention: bounce title color via alternateTitle not needed; log to console.
        if changed && lastSignature.0 != "" { NSLog("[GeoFlag] changed -> %@ (%@)", info.ip, info.country) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh when the user looks at the menu — covers rare missed events.
        scheduleCheck()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
