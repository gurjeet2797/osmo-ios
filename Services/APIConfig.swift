import Foundation

enum APIEnvironment {
    case development
    case production

    var baseURL: URL {
        switch self {
        case .development:
            URL(string: "https://hispid-kenyetta-diphtheritically.ngrok-free.dev")!
        case .production:
            URL(string: "https://osmo-ios-production.up.railway.app")!
        }
    }
}

enum APIConfig {
    #if DEBUG
    static let environment: APIEnvironment = .development
    #else
    static let environment: APIEnvironment = .production
    #endif

    static var baseURL: URL { environment.baseURL }
    static let customURLScheme = "osmo"
}
