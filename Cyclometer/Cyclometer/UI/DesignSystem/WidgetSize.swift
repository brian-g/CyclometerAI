enum WidgetSize: String, Codable, CaseIterable, Equatable {
    case oneByOne
    case twoByOne
    case twoByTwo

    /// Grid columns spanned (UX.md "Widget Size Convention": sizes are WxH).
    var columns: Int {
        switch self {
        case .oneByOne: 1
        case .twoByOne, .twoByTwo: 2
        }
    }

    /// Grid rows spanned.
    var rows: Int {
        switch self {
        case .oneByOne, .twoByOne: 1
        case .twoByTwo: 2
        }
    }
}
