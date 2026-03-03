import SwiftUI

struct FAQView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection

                    faqSection(
                        title: "Calendar",
                        icon: "calendar",
                        items: [
                            "\"What's on my calendar today?\"",
                            "\"Schedule a meeting with Sarah tomorrow at 2pm\"",
                            "\"Cancel my next meeting\"",
                            "\"Find free time this week\"",
                            "\"Move my 3pm to 4pm\"",
                        ]
                    )

                    faqSection(
                        title: "Email",
                        icon: "envelope",
                        items: [
                            "\"Do I have any unread emails?\"",
                            "\"Read my latest email from John\"",
                            "\"Search emails about the project proposal\"",
                        ]
                    )

                    faqSection(
                        title: "Reminders & Timers",
                        icon: "bell",
                        items: [
                            "\"Remind me to call mom at 5pm\"",
                            "\"Set a timer for 10 minutes\"",
                            "\"What reminders do I have?\"",
                        ]
                    )

                    faqSection(
                        title: "Navigation",
                        icon: "map",
                        items: [
                            "\"Navigate to the nearest coffee shop\"",
                            "\"How far is the airport?\"",
                            "\"Take me home\"",
                        ]
                    )

                    faqSection(
                        title: "Music",
                        icon: "music.note",
                        items: [
                            "\"Play some lo-fi music\"",
                            "\"Pause the music\"",
                            "\"Skip this song\"",
                        ]
                    )

                    faqSection(
                        title: "Device Control",
                        icon: "iphone",
                        items: [
                            "\"Turn on the flashlight\"",
                            "\"Set brightness to 50%\"",
                            "\"What's my battery level?\"",
                        ]
                    )

                    faqSection(
                        title: "Messages",
                        icon: "message",
                        items: [
                            "\"Text Sarah I'm on my way\"",
                            "\"Send a message to Mom\"",
                        ]
                    )

                    faqSection(
                        title: "Translation",
                        icon: "globe",
                        items: [
                            "\"Translate 'hello' to Spanish\"",
                            "\"How do you say 'thank you' in Japanese?\"",
                        ]
                    )

                    faqSection(
                        title: "Vision",
                        icon: "camera",
                        items: [
                            "Long-hold the orb to snap a photo",
                            "\"What is this?\" (with a photo)",
                            "\"Read this sign\" (with a photo)",
                        ]
                    )

                    faqSection(
                        title: "General",
                        icon: "sparkles",
                        items: [
                            "\"What can you help me with?\"",
                            "\"What's the weather like?\"",
                            "Ask anything — Osmo is a general AI assistant",
                        ]
                    )

                    tipsSection
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color.black)
            .navigationTitle("What Osmo Can Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Osmo is your AI-powered personal assistant.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Tap the orb, speak naturally, and Osmo will handle the rest.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func faqSection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.leading, 21)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.04))
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow.opacity(0.5))
                Text("Tips")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tap the orb to start voice input")
                Text("Long-hold the orb to take a photo")
                Text("Swipe up on the orb for settings")
                Text("Osmo remembers context within a conversation")
                Text("Say \"clear\" or tap the chat icon to start fresh")
            }
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.leading, 21)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.yellow.opacity(0.03))
                .stroke(.yellow.opacity(0.08), lineWidth: 0.5)
        )
    }
}
