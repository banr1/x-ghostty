import Foundation

extension UserDefaults {
    static var ghosttySuite: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["XGHOSTTY_USER_DEFAULTS_SUITE"]
        #else
        nil
        #endif
    }

    static var ghostty: UserDefaults {
        ghosttySuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
