// LoopFollow
// WatchProfileBridge.swift

import Combine
import Foundation
import WatchConnectivity

/// Remote profiles on the Watch. The iPhone sends the Watch the profiles, the edit limits and the commands the
/// AID app accepts. The Watch edits, confirms and hands a command back; the iPhone runs the same checks as its
/// own review (fresh profiles from Nightscout, the limits, the push size), sends it, and forwards the result.
/// Profile commands go through the iPhone because the AID app replies to LoopFollow on the iPhone.
enum WatchProfileBridge {
    // MARK: - Profiles for the Watch

    static var remote: ProfileRemote? {
        switch Storage.shared.remoteType.value {
        case .trc: return .trio
        case .loopAPNS: return .loop
        case .none: return nil
        }
    }

    /// The `therapyProfiles` entry of the Watch config, or nil when there is nothing to offer.
    static func configEntry() -> [String: Any]? {
        guard let remote, let set = Observable.shared.therapyProfiles.value else { return nil }
        let commands = remote.acceptedCommands(
            profileDocument: Storage.shared.remoteCommands.value,
            loopDeviceStatus: Storage.shared.loopRemoteCommands.value
        )
        let kinds = [ProfileCommandKind.activate, .save, .delete].filter { remote.supports($0, in: commands) }
        guard !kinds.isEmpty else { return nil }
        let canSave = kinds.contains(.save)
        // Older Loop builds upload a Default entry that only mirrors the active settings.
        let profiles = canSave ? set.profiles : set.profiles.filter { !$0.isDefault }

        var entry: [String: Any] = [
            "app": remote.appName,
            "active": set.activeName,
            "singleTarget": remote.hasSingleTarget,
            "commands": kinds.map(\.rawValue),
            "profiles": profiles.map { profile -> [String: Any] in
                var item = values(profile.values)
                item["name"] = profile.name
                item["fingerprint"] = profile.fingerprint
                item["isDefault"] = profile.isDefault
                if let blocker = ProfileEditing.blocker(for: profile, limits: set.limits, remote: remote) {
                    item["editBlocker"] = blocker
                }
                return item
            },
        ]
        if let uploadedAt = set.uploadedAt { entry["uploadedAt"] = uploadedAt.timeIntervalSince1970 }
        if let blocker = ProfileEditing.blocker(limits: set.limits, remote: remote) {
            entry["editBlocker"] = blocker
        } else if let limits = set.limits {
            entry["limits"] = limitsEntry(limits)
        }
        return entry
    }

    private static func values(_ values: TherapyProfileValues) -> [String: Any] {
        [
            "units": values.units,
            "basal": values.basal.map { [Double($0.seconds), $0.value] },
            "carbratio": values.carbRatio.map { [Double($0.seconds), $0.value] },
            "sens": values.sensitivity.map { [Double($0.seconds), $0.value] },
            "target": values.target.map { [Double($0.seconds), $0.low, $0.high] },
        ]
    }

    private static func limitsEntry(_ limits: ProfileEditLimits) -> [String: Any] {
        func range(_ range: ProfileEditLimits.Range) -> [String: Any] {
            var entry: [String: Any] = ["min": range.min, "max": range.max, "step": range.step]
            if let recommendedMin = range.recommendedMin { entry["recommendedMin"] = recommendedMin }
            if let recommendedMax = range.recommendedMax { entry["recommendedMax"] = recommendedMax }
            return entry
        }
        return [
            "units": limits.normalizedUnits,
            "basalRates": limits.allowedBasalRates,
            "carbRatio": range(limits.carbRatio),
            "sensitivity": range(limits.sensitivity),
            "target": range(limits.target),
            "segmentSeconds": limits.segmentSeconds,
            "maxSegments": limits.segmentLimit,
            "maxBasalSegments": limits.segmentLimit(for: .basal),
        ]
    }

    // MARK: - Commands from the Watch

    private static var resultWatchers: [String: AnyCancellable] = [:]

    /// Handles `["profileCommand": [...]]` from the Watch. Replies at once with `["error": message]` when nothing
    /// is sent, or `["sent": true]`; the result follows later as `["profileCommandResult": [...]]`.
    static func handle(_ request: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            guard let remote else {
                reply(["error": "Remote control is not set up in LoopFollow on the iPhone."])
                return
            }
            if ProfileCommandFlow.isAnyPending(RemoteCommandTracker.shared, remote: remote) {
                reply(["error": "Another profile command is still waiting for \(remote.appName). Try again once it has finished."])
                return
            }
            // Check against the newest profiles, exactly as the iPhone's own review does.
            ProfileCommandFlow.fetchProfileSet { current in
                switch command(from: request, current: current, remote: remote) {
                case let .failure(problem):
                    reply(["error": problem.message])
                case let .success(command):
                    send(command, to: remote, reply: reply)
                }
            }
        }
    }

    private struct Problem: Error {
        let message: String
    }

    /// The command the Watch asked for, checked against the newest profiles and the limits.
    private static func command(from request: [String: Any], current: TherapyProfileSet?, remote: ProfileRemote) -> Result<ProfileCommand, Problem> {
        guard let current else {
            return .failure(Problem(message: "LoopFollow on the iPhone could not load the profiles from Nightscout, so nothing was sent. Try again."))
        }
        guard let kind = (request["kind"] as? String).flatMap(ProfileCommandKind.init(rawValue:)) else {
            return .failure(Problem(message: "Unknown profile command."))
        }
        let name = request["name"] as? String ?? ""
        let baseFingerprint = request["baseFingerprint"] as? String

        /// The profile the Watch acted on, when it is unchanged on the phone.
        func unchanged(_ name: String) -> Result<TherapyProfile, Problem> {
            guard let profile = current.profile(named: name) else {
                return .failure(Problem(message: "“\(name)” is no longer in the list uploaded by \(remote.appName), so nothing was sent."))
            }
            guard profile.fingerprint == baseFingerprint else {
                return .failure(Problem(message: "“\(name)” changed in \(remote.appName), so nothing was sent. Open it again to see its current values."))
            }
            return .success(profile)
        }

        switch kind {
        case .activate:
            return unchanged(name).map { .activate($0) }
        case .delete:
            return unchanged(name).flatMap { profile -> Result<ProfileCommand, Problem> in
                if current.isActive(profile) { return .failure(Problem(message: "The active profile can't be deleted. Activate another profile first.")) }
                if profile.isDefault { return .failure(Problem(message: "The Default profile can't be deleted.")) }
                return .success(.delete(profile))
            }
        case .save:
            guard let limits = current.limits else {
                return .failure(Problem(message: ProfileEditing.blocker(limits: nil, remote: remote) ?? "Profiles can't be changed remotely."))
            }
            guard let values = profileValues(from: request["values"], units: limits.normalizedUnits) else {
                return .failure(Problem(message: "The profile values from the Watch could not be read."))
            }
            let newName = ProfileValidation.normalizedName(name)
            var original: TherapyProfile?
            if let originalName = request["originalName"] as? String {
                let profile: TherapyProfile
                switch unchanged(originalName) {
                case let .failure(problem): return .failure(problem)
                case let .success(found): profile = found
                }
                if let blocker = ProfileEditing.blocker(for: profile, limits: limits, remote: remote) {
                    return .failure(Problem(message: blocker))
                }
                if let reviewedActive = request["reviewedActive"] as? Bool, current.isActive(profile) != reviewedActive {
                    return .failure(Problem(message: reviewedActive
                            ? "“\(originalName)” is no longer the active profile in \(remote.appName), so nothing was sent. Review it again."
                            : "“\(originalName)” became active in \(remote.appName), so nothing was sent. Review it again."))
                }
                if newName != originalName,
                   let problem = ProfileValidation.nameProblem(newName, existingNames: current.profiles.map(\.name), originalName: originalName)
                {
                    return .failure(Problem(message: problem))
                }
                original = profile
            } else if let problem = ProfileValidation.countProblem(profileCount: current.profiles.count)
                ?? ProfileValidation.nameProblem(newName, existingNames: current.profiles.map(\.name))
            {
                return .failure(Problem(message: problem))
            }
            let command = ProfileCommand.save(name: newName, original: original, values: values)
            let problems = ProfileValidation.problems(for: command, limits: limits)
            if !problems.isEmpty {
                return .failure(Problem(message: problems.joined(separator: "\n")))
            }
            if let size = pushSize(command, remote: remote), size > ProfilePushSize.reviewLimit(for: remote) {
                return .failure(Problem(message: ProfilePushSize.tooLargeMessage(size)))
            }
            return .success(command)
        case .saveScheduledSwitches:
            return .failure(Problem(message: "Scheduled switches can be changed on the iPhone."))
        }
    }

    private static func pushSize(_ command: ProfileCommand, remote: ProfileRemote) -> Int? {
        guard case let .save(name, original, values) = command else { return nil }
        switch remote {
        case .loop:
            return LoopAPNSService().profileSavePushSize(name: name, originalName: original?.name, baseFingerprint: original?.fingerprint, values: values)
        case .trio:
            return PushNotificationManager().profileSavePushSize(name: name, originalName: original?.name, baseFingerprint: original?.fingerprint, values: values)
        }
    }

    private static func profileValues(from object: Any?, units: String) -> TherapyProfileValues? {
        guard let dict = object as? [String: Any] else { return nil }
        func items(_ key: String) -> [ProfileScheduleItem]? {
            guard let rows = dict[key] as? [[Double]] else { return nil }
            let items = rows.compactMap { row -> ProfileScheduleItem? in
                guard row.count == 2 else { return nil }
                return ProfileScheduleItem(seconds: Int(row[0]), value: row[1])
            }
            return items.count == rows.count ? items : nil
        }
        guard let basal = items("basal"), let carbRatio = items("carbratio"), let sensitivity = items("sens"),
              let targetRows = dict["target"] as? [[Double]]
        else { return nil }
        let target = targetRows.compactMap { row -> ProfileRangeItem? in
            guard row.count == 3 else { return nil }
            return ProfileRangeItem(seconds: Int(row[0]), low: row[1], high: row[2])
        }
        guard target.count == targetRows.count else { return nil }
        return TherapyProfileValues(
            units: TherapyProfileValues.normalizedUnits(dict["units"] as? String ?? units),
            basal: basal,
            carbRatio: carbRatio,
            sensitivity: sensitivity,
            target: target
        )
    }

    private static func send(_ command: ProfileCommand, to remote: ProfileRemote, reply: @escaping ([String: Any]) -> Void) {
        let key = remote.key(for: command)
        LogManager.shared.log(category: .apns, message: "Sending \(command.kind.rawValue) for the Watch")
        // Forward the reply from the AID app (or the timeout) to the Watch once it arrives.
        // Skips the current value, which may hold the result of an earlier command under this key.
        resultWatchers[key] = RemoteCommandTracker.shared.$states
            .dropFirst()
            .compactMap { $0[key] }
            .first(where: { state in
                if case .done = state { return true }
                return false
            })
            .receive(on: DispatchQueue.main)
            .sink { state in
                resultWatchers[key] = nil
                guard case let .done(success, message, outdated) = state else { return }
                RemoteCommandTracker.shared.consume(key: key)
                let result = ProfileCommandResult(success: success, message: message, outdated: outdated)
                forward([
                    "kind": command.kind.rawValue,
                    "success": success,
                    "title": ProfileCommandFlow.resultTitle(kind: command.kind, success: success, message: message, remote: remote),
                    "message": ProfileCommandFlow.resultMessage(result, remote: remote),
                ])
            }
        RemoteCommandTracker.shared.sendProfileCommand(command, to: remote) { sent, error in
            DispatchQueue.main.async {
                if sent {
                    reply(["sent": true])
                } else {
                    resultWatchers[key] = nil
                    reply(["error": error ?? "The command could not be sent."])
                }
            }
        }
    }

    /// Sends a command's result to the Watch: at once when it is reachable, queued otherwise.
    private static func forward(_ result: [String: Any]) {
        let message: [String: Any] = ["profileCommandResult": result]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }
}
