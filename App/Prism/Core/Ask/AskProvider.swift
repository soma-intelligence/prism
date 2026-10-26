//
//  AskProvider.swift
//  Prism
//

import Foundation
import Observation
import Security

/// Who writes Ask's answers.
///
/// Apple Intelligence runs on the phone: free, private and the fastest to a
/// first word, on the devices that have it. Soma's own model runs behind the
/// `ask-soma` function with an hourly allowance. The rest are the person's
/// own accounts, reached with their key, which stays in the Keychain on this
/// device and is sent only to that provider.
nonisolated enum AskProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleIntelligence
    case soma
    case openAI
    case anthropic
    case openRouter
    case azure
    /// Any server that speaks the OpenAI chat completions protocol.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .soma: "Soma"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        case .azure: "Azure OpenAI"
        case .custom: "Custom server"
        }
    }

    var detail: String {
        switch self {
        case .appleIntelligence: "On this iPhone. Free, private, fastest."
        case .soma: "Soma's model. 60 questions an hour."
        case .openAI: "Your OpenAI key"
        case .anthropic: "Your Anthropic key"
        case .openRouter: "Your OpenRouter key, any model it lists"
        case .azure: "Your Azure resource and deployment"
        case .custom: "Any OpenAI-compatible endpoint"
        }
    }

    /// Whether the provider needs the person's own key.
    var needsKey: Bool { ![.appleIntelligence, .soma].contains(self) }

    /// Whether the person types the server's address.
    var needsEndpoint: Bool { self == .azure || self == .custom }

    /// The model a fresh setup starts on.
    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5"
        case .anthropic: "claude-sonnet-5-5"
        case .openRouter: "anthropic/claude-sonnet-5.5"
        case .azure, .custom, .appleIntelligence, .soma: ""
        }
    }
}

/// What the person chose for Ask, kept on this device. The key is in the
/// Keychain; everything else in the defaults.
@MainActor
@Observable
final class AskProviderSettings {
    static let shared = AskProviderSettings()

    private let defaults: UserDefaults

    /// The provider Ask uses. Nil until the person picks one: Ask then takes
    /// Apple Intelligence where the phone has it and Soma's model elsewhere.
    var chosen: AskProvider? {
        didSet { defaults.set(chosen?.rawValue, forKey: "ask.provider") }
    }

    private var models: [String: String] {
        didSet { defaults.set(models, forKey: "ask.models") }
    }
    private var endpoints: [String: String] {
        didSet { defaults.set(endpoints, forKey: "ask.endpoints") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosen = defaults.string(forKey: "ask.provider").flatMap(AskProvider.init(rawValue:))
        models = defaults.dictionary(forKey: "ask.models") as? [String: String] ?? [:]
        endpoints = defaults.dictionary(forKey: "ask.endpoints") as? [String: String] ?? [:]
    }

    /// The provider in effect: the one chosen, else the best one this
    /// device can run.
    var effective: AskProvider {
        if let chosen { return chosen }
        return AppleIntelligence.availability == .available ? .appleIntelligence : .soma
    }

    func model(for provider: AskProvider) -> String {
        let typed = models[provider.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return typed.isEmpty ? provider.defaultModel : typed
    }

    func setModel(_ model: String, for provider: AskProvider) { models[provider.rawValue] = model }

    func endpoint(for provider: AskProvider) -> String { endpoints[provider.rawValue] ?? "" }

    func setEndpoint(_ endpoint: String, for provider: AskProvider) { endpoints[provider.rawValue] = endpoint }

    func key(for provider: AskProvider) -> String? { AskKeychain.read(provider.rawValue) }

    func setKey(_ key: String, for provider: AskProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { AskKeychain.delete(provider.rawValue) } else { AskKeychain.save(trimmed, for: provider.rawValue) }
    }

    /// What is still missing before the provider can answer, in a few words,
    /// or nil when it is ready.
    func missing(for provider: AskProvider) -> String? {
        if provider == .appleIntelligence, let reason = AppleIntelligence.availability.reason { return reason }
        if provider.needsKey, key(for: provider) == nil { return "Add your \(provider.title) key" }
        if provider.needsEndpoint, endpoint(for: provider).isEmpty { return "Add the server address" }
        if [.azure, .custom].contains(provider), model(for: provider).isEmpty {
            return provider == .azure ? "Add the deployment name" : "Add the model name"
        }
        return nil
    }
}

/// The person's provider keys, one Keychain item each, never synced and
/// readable only after the phone is first unlocked.
nonisolated enum AskKeychain {
    private static let service = "me.somalabs.ask.keys"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String, for account: String) {
        delete(account)
        var item = query(account)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Why an answer did not come, worded for the person: a title that says what
/// happened and a line that says what to do. Every provider maps its own
/// errors into one of these, so the page never shows a code.
nonisolated struct AskFailure: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The phone cannot run Apple Intelligence at all.
        case deviceNotEligible
        /// It can, but it is off in Settings.
        case intelligenceOff
        /// The model is still downloading.
        case modelNotReady
        /// The allowance is used up: questions used of the allowance.
        case limitReached(used: Int?, of: Int?)
        case missingKey
        case badKey
        case badModel
        case tooLong
        case refused
        case offline
        case server
    }

    var kind: Kind
    var title: String
    var detail: String
    /// Whether the fix is in Ask's settings, so the page offers to open them.
    var opensSettings: Bool

    static func deviceNotEligible() -> AskFailure {
        AskFailure(kind: .deviceNotEligible, title: "This iPhone can\u{2019}t run Apple Intelligence",
                   detail: "It needs an iPhone 15 Pro or later. Choose another model for Ask.", opensSettings: true)
    }

    static func intelligenceOff() -> AskFailure {
        AskFailure(kind: .intelligenceOff, title: "Apple Intelligence is off",
                   detail: "Turn it on in Settings, Apple Intelligence & Siri, or choose another model.", opensSettings: true)
    }

    static func modelNotReady() -> AskFailure {
        AskFailure(kind: .modelNotReady, title: "Apple Intelligence is still downloading",
                   detail: "Keep the iPhone on Wi\u{2011}Fi and charging, then ask again.", opensSettings: false)
    }

    static func limitReached(used: Int?, of total: Int?, retry: String?) -> AskFailure {
        let count = total.map { "\(used ?? $0) of \($0)" }
        return AskFailure(kind: .limitReached(used: used, of: total),
                          title: count.map { "You\u{2019}ve used \($0) questions this hour" } ?? "You\u{2019}ve reached this hour\u{2019}s questions",
                          detail: (retry.map { "Ask again \($0), " } ?? "Ask again in a little while, ") + "or switch to Apple Intelligence or your own key.",
                          opensSettings: true)
    }

    static func missingKey(_ provider: AskProvider) -> AskFailure {
        AskFailure(kind: .missingKey, title: "\(provider.title) needs your key",
                   detail: "Add it in Ask\u{2019}s settings. It stays on this iPhone.", opensSettings: true)
    }

    static func badKey(_ provider: AskProvider) -> AskFailure {
        AskFailure(kind: .badKey, title: "\(provider.title) refused the key",
                   detail: "Check the key in Ask\u{2019}s settings, or that the account has credit.", opensSettings: true)
    }

    static func badModel(_ provider: AskProvider, _ model: String) -> AskFailure {
        AskFailure(kind: .badModel, title: "\(provider.title) doesn\u{2019}t know \u{201C}\(model)\u{201D}",
                   detail: "Check the model name in Ask\u{2019}s settings.", opensSettings: true)
    }

    static func tooLong() -> AskFailure {
        AskFailure(kind: .tooLong, title: "This conversation is too long for the model",
                   detail: "Start a new one with the pencil at the top.", opensSettings: false)
    }

    static func refused(_ message: String?) -> AskFailure {
        AskFailure(kind: .refused, title: "The model wouldn\u{2019}t answer that",
                   detail: message.flatMap { $0.isEmpty ? nil : $0 } ?? "Try asking it another way.", opensSettings: false)
    }

    static func offline() -> AskFailure {
        AskFailure(kind: .offline, title: "No connection",
                   detail: "Check the network, or use Apple Intelligence, which works offline.", opensSettings: false)
    }

    static func server(_ provider: AskProvider, status: Int) -> AskFailure {
        AskFailure(kind: .server, title: "\(provider.title) had a problem",
                   detail: status > 0 ? "It answered with an error (\(status)). Try again in a moment." : "Try again in a moment.",
                   opensSettings: false)
    }
}
