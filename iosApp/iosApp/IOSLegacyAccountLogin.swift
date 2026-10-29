import Foundation
@preconcurrency import Shared

/// Codex (ChatGPT) and Grok (xAI) account sign-in were removed from this app.
/// These helpers only recognise providers still saved in those modes, so they
/// read as "not configured" and are never sent anywhere.
enum IOSLegacyAccountLogin {
    static func isLegacyCodexLogin(_ openAI: ProviderSetting.OpenAI) -> Bool {
        if openAI.authMode == OpenAIAuthMode.codexOauth { return true }
        guard let c = components(openAI.baseUrl), c.host == "chatgpt.com" else { return false }
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return path == "backend-api/codex" || path == "backend-api/codex/v1"
    }

    static func isLegacyGrokLogin(_ openAI: ProviderSetting.OpenAI) -> Bool {
        guard let c = components(openAI.baseUrl) else { return false }
        if c.host == "cli-chat-proxy.grok.com" { return true }
        guard c.host == "grok.com" else { return false }
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return path == "rest/app-chat" || path == "rest/app-chat/conversations"
    }

    static func isLegacyLogin(_ provider: ProviderSetting?) -> Bool {
        guard let openAI = provider as? ProviderSetting.OpenAI else { return false }
        return isLegacyCodexLogin(openAI) || isLegacyGrokLogin(openAI)
    }

    private static func components(_ raw: String) -> (host: String, path: String)? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", let host = c.host?.lowercased() else { return nil }
        return (host, c.path)
    }
}
