// LoopFollow
// SenderAvatarStore.swift

import SwiftUI
import UIKit

/// The picture shown for each remote bolus sender, chosen on this device and remembered by name.
final class SenderAvatarStore: ObservableObject {
    static let shared = SenderAvatarStore()

    enum Avatar: Codable, Equatable {
        case emoji(String)
        /// A square JPEG in the avatars folder.
        case photo(fileName: String)
    }

    @Published private(set) var avatars: [String: Avatar]
    /// Bumped when a photo file changes, so views reload it.
    @Published private(set) var revision = 0

    private static let storageKey = "senderAvatars"
    private var imageCache: [String: UIImage] = [:]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        avatars = data.flatMap { try? JSONDecoder().decode([String: Avatar].self, from: $0) } ?? [:]
    }

    /// Names match without regard to letter case or surrounding spaces.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func avatar(for name: String) -> Avatar? {
        avatars[Self.key(name)]
    }

    func image(for name: String) -> UIImage? {
        guard case let .photo(fileName) = avatar(for: name) else { return nil }
        if let cached = imageCache[fileName] { return cached }
        guard let image = UIImage(contentsOfFile: Self.folder.appendingPathComponent(fileName).path) else { return nil }
        imageCache[fileName] = image
        return image
    }

    func setEmoji(_ emoji: String, for name: String) {
        removePhotoFile(for: name)
        set(.emoji(emoji), for: name)
    }

    /// Stores the photo cropped to a square and scaled down.
    func setPhoto(_ image: UIImage, for name: String) {
        guard let data = Self.square(image, side: 256).jpegData(compressionQuality: 0.85) else { return }
        removePhotoFile(for: name)
        let fileName = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: Self.folder.appendingPathComponent(fileName), options: .atomic)
            set(.photo(fileName: fileName), for: name)
            revision += 1
        } catch {
            LogManager.shared.log(category: .general, message: "Saving sender photo failed: \(error.localizedDescription)")
        }
    }

    func remove(for name: String) {
        removePhotoFile(for: name)
        var all = avatars
        all[Self.key(name)] = nil
        save(all)
    }

    private func set(_ avatar: Avatar, for name: String) {
        var all = avatars
        all[Self.key(name)] = avatar
        save(all)
    }

    private func save(_ all: [String: Avatar]) {
        avatars = all
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func removePhotoFile(for name: String) {
        guard case let .photo(fileName) = avatar(for: name) else { return }
        imageCache[fileName] = nil
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(fileName))
    }

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SenderAvatars", isDirectory: true)
    }

    private static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        let size = image.size
        let crop = min(size.width, size.height)
        let scale = side / max(crop, 1)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
