import UIKit

final class MediaManager: Sendable {
    static let shared = MediaManager()

    private let session: URLSession = .shared
    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    /// Download an attachment to a temporary file, returning the local file URL.
    func downloadAttachment(_ attachment: Attachment) async throws -> URL {
        // Check cache
        let cacheKey = attachment.id as NSString
        if let cached = cache.object(forKey: cacheKey) {
            let tempURL = tempFileURL(for: attachment)
            try (cached as Data).write(to: tempURL)
            return tempURL
        }

        let url = try attachmentURL(for: attachment)
        var request = URLRequest(url: url)
        if let token = KeychainHelper.read(.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MediaError.downloadFailed
        }

        cache.setObject(data as NSData, forKey: cacheKey, cost: data.count)

        let tempURL = tempFileURL(for: attachment)
        try data.write(to: tempURL)
        return tempURL
    }

    /// Download and create a thumbnail image for an image attachment.
    func loadImageThumbnail(_ attachment: Attachment, maxSize: CGFloat = 300) async throws -> UIImage {
        let fileURL = try await downloadAttachment(attachment)
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            throw MediaError.invalidImage
        }

        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func attachmentURL(for attachment: Attachment) throws -> URL {
        let base = APIConfig.baseURL
        guard let url = URL(string: attachment.url, relativeTo: base) else {
            throw MediaError.invalidURL
        }
        return url
    }

    private func tempFileURL(for attachment: Attachment) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("\(attachment.id)_\(attachment.filename)")
    }
}

enum MediaError: Error, LocalizedError {
    case invalidURL
    case downloadFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid attachment URL"
        case .downloadFailed: "Failed to download attachment"
        case .invalidImage: "Could not load image from attachment"
        }
    }
}
