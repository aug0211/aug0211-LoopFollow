// LoopFollow
// WatchProfileCommandSender.swift

import Foundation
import WatchConnectivity
import WatchKit

/// Hands profile commands to LoopFollow on the iPhone, which checks and sends them and reports the result.
final class WatchProfileCommandSender: ObservableObject {
    static let shared = WatchProfileCommandSender()

    enum State: Equatable {
        case idle
        /// Handed to the iPhone, which is checking it.
        case sending
        /// Sent to the AID app; waiting for its reply.
        case waiting
        case finished(success: Bool, title: String, message: String)
    }

    @Published private(set) var state: State = .idle

    private var timeout: DispatchWorkItem?

    var isBusy: Bool { state == .sending || state == .waiting }

    func activate(_ profile: WatchTherapyProfile) {
        send(["kind": "activate", "name": profile.name, "baseFingerprint": profile.fingerprint])
    }

    func delete(_ profile: WatchTherapyProfile) {
        send(["kind": "delete", "name": profile.name, "baseFingerprint": profile.fingerprint])
    }

    /// Creates `name` when `original` is nil; otherwise updates `original`, renaming it when `name` differs.
    func save(name: String, original: WatchTherapyProfile?, values: WatchProfileValues, singleTarget: Bool, reviewedActive: Bool) {
        var request: [String: Any] = [
            "kind": "save",
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "values": values.dictionary(singleTarget: singleTarget),
        ]
        if let original {
            request["originalName"] = original.name
            request["baseFingerprint"] = original.fingerprint
            request["reviewedActive"] = reviewedActive
        }
        send(request)
    }

    /// Clears a finished result once it has been shown.
    func reset() {
        guard !isBusy else { return }
        state = .idle
    }

    private func send(_ request: [String: Any]) {
        guard !isBusy else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            finish(success: false, title: "Not Sent", message: "The connection to the iPhone isn't ready. Try again.")
            return
        }
        state = .sending
        session.sendMessage(["profileCommand": request], replyHandler: { reply in
            DispatchQueue.main.async {
                if let error = reply["error"] as? String {
                    self.finish(success: false, title: "Not Sent", message: error)
                } else if self.state == .sending {
                    self.state = .waiting
                    self.startTimeout()
                }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.finish(success: false, title: "iPhone Not Reachable", message: "Profile changes are sent by LoopFollow on the iPhone. Keep the iPhone nearby, open LoopFollow on it, and try again.")
            }
        })
    }

    /// The iPhone forwards the AID app's reply, or its own timeout, as `profileCommandResult`.
    func receive(_ result: [String: Any]) {
        DispatchQueue.main.async {
            guard self.isBusy else { return }
            self.finish(
                success: result["success"] as? Bool ?? false,
                title: result["title"] as? String ?? "Profile Command",
                message: result["message"] as? String ?? ""
            )
        }
    }

    private func startTimeout() {
        timeout?.cancel()
        // The iPhone gives up after 3 minutes and reports that; this only covers a lost report.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .waiting else { return }
            self.finish(success: false, title: "No Result", message: "The result didn't reach the Watch. The change may still be applied; check the profile list on the iPhone before sending again.")
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 240, execute: work)
    }

    private func finish(success: Bool, title: String, message: String) {
        timeout?.cancel()
        timeout = nil
        state = .finished(success: success, title: title, message: message)
        WKInterfaceDevice.current().play(success ? .success : .failure)
    }
}
