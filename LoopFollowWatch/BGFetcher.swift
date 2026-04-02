// LoopFollow
// BGFetcher.swift

import Combine
import Foundation

class BGFetcher: ObservableObject {
    @Published var currentBG: BGReading?
    @Published var lastError: String?

    private var timer: Timer?
    private var dexSessionToken: String?

    private let dexcomUserAgent = "Dexcom Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0"
    private let dexcomApplicationId = "d89443d2-327c-4a6f-89e5-496bbb0317db"

    func start(config: WatchConfig) {
        stop()
        fetch(config: config)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetch(config: config)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch(config: WatchConfig) {
        if config.hasDexcomCredentials {
            fetchDexcom(config: config)
        } else if config.hasNightscoutURL {
            fetchNightscout(config: config)
        }
    }

    // MARK: - Nightscout

    private func fetchNightscout(config: WatchConfig) {
        var components = URLComponents(string: config.nsURL)
        components?.path = "/api/v1/entries.json"

        var queryItems = [URLQueryItem]()
        if !config.nsToken.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: config.nsToken))
        }
        queryItems.append(URLQueryItem(name: "count", value: "2"))
        queryItems.append(URLQueryItem(name: "find[type][$ne]", value: "cal"))
        components?.queryItems = queryItems

        guard let url = components?.url else {
            DispatchQueue.main.async { self.lastError = "Invalid Nightscout URL" }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { self.lastError = "No data received" }
                return
            }

            self.parseNightscoutResponse(data: data)
        }.resume()
    }

    private func parseNightscoutResponse(data: Data) {
        struct NSEntry: Decodable {
            var sgv: Double?
            var mbg: Double?
            var glucose: Double?
            var date: TimeInterval
            var direction: String?

            var bgValue: Int? {
                if let sgv = sgv { return Int(sgv.rounded()) }
                if let mbg = mbg { return Int(mbg.rounded()) }
                if let glucose = glucose { return Int(glucose.rounded()) }
                return nil
            }
        }

        do {
            let entries = try JSONDecoder().decode([NSEntry].self, from: data)
            guard let latest = entries.first, let bgValue = latest.bgValue else {
                DispatchQueue.main.async { self.lastError = "No BG entries" }
                return
            }

            // NS timestamps are in milliseconds
            let timestamp = Date(timeIntervalSince1970: latest.date / 1000)
            let delta: Int?
            if entries.count >= 2, let priorBG = entries[1].bgValue {
                delta = bgValue - priorBG
            } else {
                delta = nil
            }

            let direction = latest.direction ?? ""
            let reading = BGReading(
                bgValue: bgValue,
                direction: BGReading.directionArrow(direction),
                timestamp: timestamp,
                delta: delta
            )

            DispatchQueue.main.async {
                self.currentBG = reading
                self.lastError = nil
            }
        } catch {
            DispatchQueue.main.async { self.lastError = "Parse error" }
        }
    }

    private func fallbackToNightscout(config: WatchConfig, dexError: String) {
        if config.hasNightscoutURL {
            fetchNightscout(config: config)
        } else {
            DispatchQueue.main.async { self.lastError = dexError }
        }
    }

    // MARK: - Dexcom Share

    private func fetchDexcom(config: WatchConfig, retryCount: Int = 0) {
        if let token = dexSessionToken {
            fetchDexcomGlucose(config: config, sessionToken: token, retryCount: retryCount)
        } else {
            authenticateDexcom(config: config, retryCount: retryCount)
        }
    }

    private func authenticateDexcom(config: WatchConfig, retryCount: Int) {
        let url = URL(string: config.dexServerURL + "/ShareWebServices/Services/General/AuthenticatePublisherAccount")!
        let body: [String: Any] = [
            "accountName": config.dexUsername,
            "password": config.dexPassword,
            "applicationId": dexcomApplicationId,
        ]

        dexcomPOST(url: url, body: body) { [weak self] error, response in
            guard let self = self else { return }
            if let error = error {
                self.fallbackToNightscout(config: config, dexError: "Dexcom auth failed: \(error.localizedDescription)")
                return
            }

            guard let response = response,
                  let data = response.data(using: .utf8),
                  let accountId = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
            else {
                self.fallbackToNightscout(config: config, dexError: "Dexcom auth: invalid response")
                return
            }

            self.loginDexcom(config: config, accountId: accountId, retryCount: retryCount)
        }
    }

    private func loginDexcom(config: WatchConfig, accountId: String, retryCount: Int) {
        let url = URL(string: config.dexServerURL + "/ShareWebServices/Services/General/LoginPublisherAccountById")!
        let body: [String: Any] = [
            "accountId": accountId,
            "password": config.dexPassword,
            "applicationId": dexcomApplicationId,
        ]

        dexcomPOST(url: url, body: body) { [weak self] error, response in
            guard let self = self else { return }
            if let error = error {
                self.fallbackToNightscout(config: config, dexError: "Dexcom login failed: \(error.localizedDescription)")
                return
            }

            guard let response = response,
                  let data = response.data(using: .utf8),
                  let token = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
            else {
                self.fallbackToNightscout(config: config, dexError: "Dexcom login: invalid response")
                return
            }

            self.dexSessionToken = token
            self.fetchDexcomGlucose(config: config, sessionToken: token, retryCount: retryCount)
        }
    }

    private func fetchDexcomGlucose(config: WatchConfig, sessionToken: String, retryCount: Int) {
        var components = URLComponents(string: config.dexServerURL + "/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues")!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionToken),
            URLQueryItem(name: "minutes", value: "1440"),
            URLQueryItem(name: "maxCount", value: "2"),
        ]

        dexcomPOST(url: components.url!, body: nil) { [weak self] error, response in
            guard let self = self else { return }
            if let error = error {
                self.fallbackToNightscout(config: config, dexError: "Dexcom fetch failed: \(error.localizedDescription)")
                return
            }

            guard let response = response,
                  let data = response.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data, options: []),
                  let sgvs = decoded as? [[String: Any]]
            else {
                // Token may be expired, retry
                if retryCount < 2 {
                    self.dexSessionToken = nil
                    self.fetchDexcom(config: config, retryCount: retryCount + 1)
                } else {
                    self.fallbackToNightscout(config: config, dexError: "Dexcom: failed after retries")
                }
                return
            }

            self.parseDexcomResponse(config: config, sgvs: sgvs)
        }
    }

    private func parseDexcomResponse(config: WatchConfig, sgvs: [[String: Any]]) {
        let trendMap = [
            "": 0, "DoubleUp": 1, "SingleUp": 2, "FortyFiveUp": 3,
            "Flat": 4, "FortyFiveDown": 5, "SingleDown": 6, "DoubleDown": 7,
            "NotComputable": 8, "RateOutOfRange": 9,
        ]

        let trendTable = [
            "NONE", "DoubleUp", "SingleUp", "FortyFiveUp", "Flat",
            "FortyFiveDown", "SingleDown", "DoubleDown", "NOT COMPUTABLE", "RATE OUT OF RANGE",
        ]

        var readings: [(bgValue: Int, direction: String, timestamp: Date)] = []

        for sgv in sgvs {
            guard let glucose = sgv["Value"] as? Int,
                  let wt = sgv["WT"] as? String
            else { continue }

            // Parse trend
            let trendIndex: Int
            if let trendString = sgv["Trend"] as? String {
                trendIndex = trendMap[trendString] ?? 0
            } else if let trendInt = sgv["Trend"] as? Int {
                trendIndex = trendInt
            } else {
                trendIndex = 0
            }

            let direction = trendIndex < trendTable.count ? trendTable[trendIndex] : "NONE"

            // Parse date from "/Date(1234567890000)/" format
            guard let timestamp = parseDexcomDate(wt) else { continue }

            readings.append((bgValue: glucose, direction: direction, timestamp: timestamp))
        }

        guard let latest = readings.first else {
            self.fallbackToNightscout(config: config, dexError: "No Dexcom readings")
            return
        }

        let delta: Int?
        if readings.count >= 2 {
            delta = latest.bgValue - readings[1].bgValue
        } else {
            delta = nil
        }

        let reading = BGReading(
            bgValue: latest.bgValue,
            direction: BGReading.directionArrow(latest.direction),
            timestamp: latest.timestamp,
            delta: delta
        )

        DispatchQueue.main.async {
            self.currentBG = reading
            self.lastError = nil
        }
    }

    private func parseDexcomDate(_ wt: String) -> Date? {
        guard let range = wt.range(of: "\\((.*)\\)", options: .regularExpression),
              let epoch = Double(wt[range].dropFirst().dropLast())
        else { return nil }
        return Date(timeIntervalSince1970: epoch / 1000)
    }

    private func dexcomPOST(url: URL, body: [String: Any]?, completion: @escaping (Error?, String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(dexcomUserAgent, forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(error, nil)
            } else if let data = data {
                completion(nil, String(data: data, encoding: .utf8))
            } else {
                completion(nil, nil)
            }
        }.resume()
    }
}
