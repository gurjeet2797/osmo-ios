import Foundation

/// Shared configuration accessible by both the main app and share extension.
enum SharedConfig {
    static var baseURL: String {
        #if DEBUG
        return "https://hispid-kenyetta-diphtheritically.ngrok-free.dev"
        #else
        return "https://osmo-ios-production.up.railway.app"
        #endif
    }
}
