/// The widget kinds Soma ships. Raw values are the WidgetKit kind strings.
public enum WidgetKind: String, CaseIterable, Sendable {
    case scores = "SomaScores"
    case vitals = "SomaVitals"
    case strain = "SomaStrain"
    case fuel = "SomaFuel"
    case log = "SomaLog"
}

/// The Control Center controls Soma ships. Raw values are the WidgetKit kind
/// strings. `startCapture` is only registered in Debug builds.
public enum ControlKind: String, CaseIterable, Sendable {
    case logWater = "SomaLogWater"
    case logCoffee = "SomaLogCoffee"
    case startCapture = "SomaStartCapture"
}
