//
//  WatchLayout.swift
//  SahilStatsLiteWatch
//
//  Auto-detects Apple Watch size and provides adaptive dimensions.
//  Supports Series 8 (45mm, 198pt wide) and Ultra 2 (49mm, 205pt wide).
//

import WatchKit

struct WatchLayout {

    enum Size: String {
        case compact   // 40-41mm (SE, Series 7/8/9 small)
        case regular   // 44-45mm (Series 4-9, SE large)
        case ultra     // 49mm (Ultra, Ultra 2)
    }

    let size: Size
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    // MARK: - Detection

    static let current: WatchLayout = {
        let bounds = WKInterfaceDevice.current().screenBounds
        let width = bounds.width

        let size: Size
        if width >= 200 {
            size = .ultra      // 205pt - Ultra/Ultra 2
        } else if width >= 180 {
            size = .regular    // 184-198pt - 44mm/45mm
        } else {
            size = .compact    // 162-176pt - 40mm/41mm
        }

        return WatchLayout(size: size, screenWidth: width, screenHeight: bounds.height)
    }()

    var isUltra: Bool { size == .ultra }
    var isCompact: Bool { size == .compact }

    // MARK: - Scoring View Dimensions

    /// Score number font size (the big "42 - 38" display)
    var scoreFontSize: CGFloat {
        switch size {
        case .compact: return 34
        case .regular: return 38
        case .ultra:   return 42
        }
    }

    /// Team name font below score
    var teamNameFontSize: CGFloat {
        switch size {
        case .compact: return 9
        case .regular: return 9
        case .ultra:   return 10
        }
    }

    /// Spacing between score number and team name
    var scoreZoneSpacing: CGFloat {
        switch size {
        case .compact: return 1
        case .regular: return 2
        case .ultra:   return 4
        }
    }

    /// Clock font size
    var clockFontSize: CGFloat {
        switch size {
        case .compact: return 15
        case .regular: return 17
        case .ultra:   return 20
        }
    }

    /// Vertical padding around clock area
    var clockVerticalPadding: CGFloat {
        switch size {
        case .compact: return 3
        case .regular: return 4
        case .ultra:   return 6
        }
    }

    /// "+1" feedback font size
    var feedbackFontSize: CGFloat {
        switch size {
        case .compact: return 16
        case .regular: return 18
        case .ultra:   return 20
        }
    }

    // MARK: - Layout Flags

    /// Combine live indicator + period on one line (saves ~20pt vertical)
    var combinedHeader: Bool { !isUltra }

    /// Show "running" / "hold to end" below clock
    var showClockHelper: Bool { isUltra }

    /// Show swipe hint to Stats tab
    var showSwipeHint: Bool { isUltra }
}
