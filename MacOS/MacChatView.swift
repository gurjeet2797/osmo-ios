import SwiftUI

struct MacChatView: View {
    @State private var viewModel = MacAppViewModel()
    @Environment(AuthManager.self) private var authManager
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Osmo")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    viewModel.clearChat()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let messages = viewModel.currentConversation?.messages {
                            ForEach(messages) { message in
                                MacMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if viewModel.isRecording, !viewModel.liveTranscript.isEmpty {
                            HStack {
                                Spacer(minLength: 40)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.red.opacity(0.8))
                                        .frame(width: 6, height: 6)
                                    Text(viewModel.liveTranscript)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .italic()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.06))
                                )
                            }
                            .id("live-transcription")
                        }

                        if viewModel.isLoading {
                            HStack {
                                MacTypingIndicator()
                                Spacer()
                            }
                            .id("typing")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.currentConversation?.messages.count) { _, _ in
                    if let last = viewModel.currentConversation?.messages.last {
                        withAnimation(.smooth(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar
            HStack(spacing: 10) {
                // Mic button
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecordingAndSend()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.isRecording ? .red.opacity(0.8) : .white.opacity(0.4))
                        .symbolEffect(.pulse, isActive: viewModel.isRecording)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)

                TextField("Type something...", text: $viewModel.inputText, axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.inputText.isEmpty ? .white.opacity(0.15) : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.06))
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .task {
            viewModel.authManager = authManager
            viewModel.loadPersistedConversations()
            viewModel.addGreetingIfNeeded()
        }
    }
}

// MARK: - Mac Message Bubble

private struct MacMessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            Group {
                if message.isUser {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(2)
                } else {
                    MarkdownContentView(blocks: MarkdownParser.parse(message.content))
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(message.isUser
                          ? Color.white.opacity(0.1)
                          : Color.white.opacity(0.04))
            )
            .textSelection(.enabled)

            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Typing Indicator

private struct MacTypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(phase == index ? 0.6 : 0.2))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .onAppear {
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
}
