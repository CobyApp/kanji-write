/// How the browse list is organized. `rawValue` is the `@AppStorage` value.
public enum Classification: String, CaseIterable, Sendable {
    case jlpt, grade

    public var label: String {
        switch self {
        case .jlpt: "JLPT別"
        case .grade: "学年別"
        }
    }
}
