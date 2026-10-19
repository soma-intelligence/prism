#if canImport(AppIntents)
import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension LogItem.Kind: AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Drink"
    public static let caseDisplayRepresentations: [LogItem.Kind: DisplayRepresentation] = [
        .water: "Water",
        .coffee: "Coffee",
    ]
}

/// Logs one drink from a widget button, without opening the app.
public struct LogDrinkIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log drink"
    public static let openAppWhenRun = false

    @Parameter(title: "Drink")
    public var kind: LogItem.Kind

    @Parameter(title: "Amount (ml)")
    public var ml: Double

    /// One drink's worth: Shortcuts can pass any number, and the inbox takes
    /// only this.
    public static let mlRange: ClosedRange<Double> = 1...2000

    public init() {
        kind = .water
        ml = LogInbox.defaultMl
    }

    public init(kind: LogItem.Kind, ml: Double = LogInbox.defaultMl) {
        self.kind = kind
        self.ml = ml
    }

    public func perform() async throws -> some IntentResult {
        guard Self.mlRange.contains(ml) else { throw LogIntentError.invalidAmount }
        guard let inbox = LogInbox.shared else { throw LogIntentError.noAppGroup }
        try inbox.append(LogItem(kind: kind, ml: ml, date: .now))
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.log.rawValue)
        #endif
        return .result()
    }
}

public enum LogIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAppGroup
    case invalidAmount

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAppGroup: "Soma could not save this drink."
        case .invalidAmount: "Soma logs a drink of 1 to 2000 ml."
        }
    }
}

/// Lets the Prism app and the widget extension share these intents.
public struct SomaWidgetIntents: AppIntentsPackage {}
#endif
