//
//  DistributionChannel.swift
//  BlinkBreak
//
//  Where this build came from. Uses StoreKit's AppTransaction, which replaces
//  the deprecated `Bundle.appStoreReceiptURL` check.
//

import StoreKit

enum DistributionChannel {

    /// True for TestFlight builds (the App Store sandbox environment).
    static func isTestFlight() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment == .sandbox
        }
    }
}
