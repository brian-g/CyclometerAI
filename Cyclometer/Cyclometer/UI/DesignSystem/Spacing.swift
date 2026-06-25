import CoreGraphics

enum Spacing {
    static let unit: CGFloat = 4

    // Standard scale
    static let xs: CGFloat = unit       //  4 — tight gaps, small padding
    static let sm: CGFloat = unit * 2   //  8 — widget internal padding
    static let md: CGFloat = unit * 3   // 12 — control bar padding, stack spacing
    static let lg: CGFloat = unit * 4   // 16 — outer horizontal padding

    // Larger layout dimensions
    static let xl: CGFloat   = unit * 6  // 24
    static let xxl: CGFloat  = unit * 9  // 36 — grabber width, sensor icon size
    static let xxxl: CGFloat = unit * 10 // 40 — accessory ring progress view

    // Semantic component dimensions
    static let radarColumnWidth: CGFloat = xl  // 24 — Varia sidebar strip (S06 spec)

    // Fixed UI affordances (named, not forced onto the grid)
    static let tapTarget: CGFloat     = unit * 13 // 52 — HIG minimum button tap target
    static let grabberHeight: CGFloat = unit       //  4 — sheet grabber bar height
    static let pageIndicatorDot: CGFloat = 7       //  7 — dashboard paging indicator dot
    static let hrBorderWidth: CGFloat = 3          //  3 — HR zone left accent bar
    static let strokeThin: CGFloat    = 1.5        //  1.5 — thin border stroke

    // Corner radii
    static let cornerSm: CGFloat = unit      //  4
    static let cornerMd: CGFloat = unit * 3  // 12
}
