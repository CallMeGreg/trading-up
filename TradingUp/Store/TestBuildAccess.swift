enum TestBuildAccess {
    /// Both the dedicated compiler condition and the exact isolated app identity
    /// are required. DEBUG, TestFlight receipts, and runtime preferences never qualify.
    static func allowsAutomaticUnlock(bundleIdentifier: String?) -> Bool {
        #if TRADING_UP_TEST_APP
        return bundleIdentifier == "com.callmegreg.tradingup.test"
        #else
        return false
        #endif
    }
}
