import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let containerView = UIView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedContent()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.06, alpha: 1.0)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        containerView.layer.cornerRadius = 20
        view.addSubview(containerView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Saving to Osmo..."
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textAlignment = .center
        containerView.addSubview(statusLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        containerView.addSubview(spinner)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 260),
            containerView.heightAnchor.constraint(equalToConstant: 120),

            spinner.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 28),

            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
        ])
    }

    private func processSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(success: false, message: "No content found")
            return
        }

        var collectedTexts: [String] = []
        let group = DispatchGroup()

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                        defer { group.leave() }
                        if let text = data as? String, !text.isEmpty {
                            collectedTexts.append(text)
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, error in
                        defer { group.leave() }
                        if let url = data as? URL {
                            collectedTexts.append(url.absoluteString)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let combined = collectedTexts.joined(separator: "\n\n")
            guard !combined.isEmpty else {
                self.finish(success: false, message: "No text to save")
                return
            }
            self.sendToBackend(text: combined)
        }
    }

    private func sendToBackend(text: String) {
        // Read auth token from shared keychain (app group)
        guard let token = SharedKeychain.readToken() else {
            finish(success: false, message: "Not signed in to Osmo")
            return
        }

        let baseURL = SharedConfig.baseURL
        guard let url = URL(string: baseURL + "/messages/index") else {
            finish(success: false, message: "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "text": text,
            "source": "share_extension",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let error {
                    self?.finish(success: false, message: "Failed: \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    self?.finish(success: false, message: "Server error (\(http.statusCode))")
                } else {
                    self?.finish(success: true, message: "Saved to Osmo")
                }
            }
        }.resume()
    }

    private func finish(success: Bool, message: String) {
        spinner.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = success
            ? UIColor.white.withAlphaComponent(0.8)
            : UIColor.red.withAlphaComponent(0.8)

        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.8 : 1.5)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
