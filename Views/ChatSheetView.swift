import SwiftUI

struct ChatSheetView: View {
    @Bindable var viewModel: AppViewModel
    @FocusState private var isInputFocused: Bool

    private var hasMessages: Bool {
        !(viewModel.currentConversation?.messages.isEmpty ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            Text("Osmo")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 14)
                .padding(.bottom, hasMessages ? 6 : 0)

            if hasMessages || viewModel.isRecording {
                messagesView
            } else {
                suggestionsView
            }

            // Confirmation banner
            if let confirmation = viewModel.pendingConfirmation {
                ConfirmationBannerView(
                    prompt: confirmation.prompt,
                    onConfirm: { viewModel.confirmPlan() },
                    onDecline: { viewModel.declineConfirmation() }
                )
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }

            // Status toast
            if let status = viewModel.statusMessage {
                statusToast(status)
            }

            inputBar
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(white: 0.06))
        .presentationCornerRadius(28)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
    }

    private var suggestionsView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Subtitle — replace with your prompt
            Text("ask anything · explore ideas")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 24)

            FlowLayout(spacing: 10) {
                ForEach(viewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.selectSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background {
                                Capsule()
                                    .fill(.white.opacity(0.06))
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            }
                    }
                    .adaptiveGlass(in: .capsule)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if let messages = viewModel.currentConversation?.messages {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageBubble(message: message, viewModel: viewModel)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.97, anchor: message.isUser ? .bottomTrailing : .bottomLeading)),
                                    removal: .opacity
                                ))
                        }
                    }

                    // Live transcription preview
                    if viewModel.isRecording, !viewModel.liveTranscript.isEmpty {
                        liveTranscriptionBubble
                            .id("live-transcription")
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
                    }

                    if viewModel.isLoading {
                        TypingIndicator()
                            .id("typing")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.currentConversation?.messages.count)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.currentConversation?.messages.count) { _, _ in
                withAnimation(.smooth(duration: 0.4)) {
                    if viewModel.isLoading {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else if let lastMessage = viewModel.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, newValue in
                if !newValue, let lastMessage = viewModel.currentConversation?.messages.last {
                    withAnimation(.smooth(duration: 0.4)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.liveTranscript) { _, _ in
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo("live-transcription", anchor: .bottom)
                }
            }
        }
    }

    private var liveTranscriptionBubble: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 8) {
                Circle()
                    .fill(.red.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.5), radius: 4)
                Text(viewModel.liveTranscript)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .italic()
                    .lineSpacing(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.06))
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private func statusToast(_ status: String) -> some View {
        HStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .scaleEffect(0.7)
            } else {
                Image(systemName: status.hasPrefix("Failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(status.hasPrefix("Failed") ? .red.opacity(0.8) : .green.opacity(0.8))
            }
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.white.opacity(0.06))
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
        .padding(.bottom, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            // Microphone button
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecordingAndSend()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.isRecording ? .red.opacity(0.8) : .white.opacity(0.4))
                    .symbolEffect(.pulse, isActive: viewModel.isRecording)
            }
            .disabled(viewModel.isLoading)

            // Placeholder — replace with your input prompt
            TextField("Type something...", text: $viewModel.inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.85))
                .tint(.white.opacity(0.6))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    viewModel.sendMessage()
                }

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.inputText.isEmpty ? .white.opacity(0.15) : .white.opacity(0.9))
                    .scaleEffect(viewModel.inputText.isEmpty ? 0.9 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.inputText.isEmpty)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.currentConversation?.messages.count ?? 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.white.opacity(0.06))
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    @Bindable var viewModel: AppViewModel
    @State private var appeared: Bool = false
    @State private var showCategories: Bool = false

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.isUser { Spacer(minLength: 60) }

                VStack(alignment: .leading, spacing: 8) {
                    Text(message.content)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(message.isUser ? 0.9 : 0.8))
                        .lineSpacing(3)

                    if !message.attachments.isEmpty {
                        ForEach(message.attachments) { attachment in
                            AttachmentView(attachment: attachment)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(message.isUser
                              ? Color.white.opacity(0.1)
                              : Color.white.opacity(0.04))
                        .stroke(
                            message.isUser
                                ? Color.white.opacity(0.08)
                                : Color.white.opacity(0.04),
                            lineWidth: 0.5
                        )
                )

                if !message.isUser { Spacer(minLength: 40) }
            }
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            // Category tabs for response messages
            if !message.isUser && message.categories != nil {
                CategoryTabsView(message: message, viewModel: viewModel, showCategories: $showCategories)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
            }

            // Tags
            if !message.isUser, let tags = message.tags, !tags.isEmpty {
                TagsRow(tags: tags)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

// MARK: - Category Tabs

struct CategoryTabsView: View {
    let message: Message
    @Bindable var viewModel: AppViewModel
    @Binding var showCategories: Bool
    @State private var selectedCategory: AppViewModel.CategoryType? = nil

    private let categoryIcons: [AppViewModel.CategoryType: String] = [
        .category1: "atom",
        .category2: "function",
        .category3: "heart",
        .category4: "sparkles"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(AppViewModel.CategoryType.allCases, id: \.self) { category in
                    let hasContent = viewModel.categoryText(for: category, in: message) != nil
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if selectedCategory == category {
                                selectedCategory = nil
                            } else {
                                selectedCategory = category
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: categoryIcons[category] ?? "circle")
                                .font(.system(size: 10))
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selectedCategory == category ? .white.opacity(0.95) : .white.opacity(0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? .white.opacity(0.12) : .white.opacity(0.04))
                                .stroke(selectedCategory == category ? .white.opacity(0.15) : .clear, lineWidth: 0.5)
                        )
                    }
                    .disabled(!hasContent)
                    .opacity(hasContent ? 1 : 0.3)
                }
            }

            if let category = selectedCategory, let text = viewModel.categoryText(for: category, in: message) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.03))
                            .stroke(.white.opacity(0.06), lineWidth: 0.5)
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Tags Row

struct TagsRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))

                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.04))
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(phase == index ? 0.7 : 0.2))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == index ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: phase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
            )
            Spacer()
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        Task {
            while !Task.isCancelled {
                for i in 0..<3 {
                    phase = i
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (positions, CGSize(width: totalWidth, height: currentY + lineHeight))
    }
}
