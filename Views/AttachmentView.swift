import QuickLook
import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment

    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var localFileURL: URL?
    @State private var showPreview = false

    var body: some View {
        Button {
            openFullPreview()
        } label: {
            HStack(spacing: 12) {
                attachmentIcon
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)

                    Text(formattedSize)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.06))
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task {
            if attachment.isImage {
                await loadThumbnail()
            }
        }
        .quickLookPreview($previewURL)
    }

    @State private var previewURL: URL?

    @ViewBuilder
    private var attachmentIcon: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if attachment.isImage {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
        } else if attachment.isPDF {
            RoundedRectangle(cornerRadius: 8)
                .fill(.red.opacity(0.15))
                .overlay {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 16))
                        .foregroundStyle(.red.opacity(0.7))
                }
        } else if attachment.isVideo {
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.opacity(0.15))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue.opacity(0.7))
                }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "doc")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private var formattedSize: String {
        let bytes = attachment.size
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func loadThumbnail() async {
        do {
            let image = try await MediaManager.shared.loadImageThumbnail(attachment)
            thumbnail = image
        } catch {
            // Silently fail — icon fallback is fine
        }
    }

    private func openFullPreview() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let url = try await MediaManager.shared.downloadAttachment(attachment)
                previewURL = url
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
