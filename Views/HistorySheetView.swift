import SwiftUI

struct HistorySheetView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Recent")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if viewModel.conversations.isEmpty {
                Spacer()
                Text("no recent conversations")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.conversations.reversed()) { conversation in
                            HistoryRow(conversation: conversation) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    viewModel.resumeConversation(conversation)
                                }
                            } onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.deleteConversation(conversation)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(white: 0.06))
        .presentationCornerRadius(28)
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let conversation: Conversation
    let onTap: () -> Void
    let onDelete: () -> Void

    private var preview: String {
        conversation.messages.first(where: { $0.isUser })?.content ?? "Empty conversation"
    }

    private var messageCount: Int {
        conversation.messages.count
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.createdAt, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(timeAgo)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))

                        Text("\u{00B7}")
                            .foregroundStyle(.white.opacity(0.2))

                        Text("\(messageCount) messages")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.04))
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
