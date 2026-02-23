import Foundation
import AppKit

@MainActor
class OfflineLicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case licensed
    }
    
    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = "OFFLINE-PREMIUM"
    @Published var isValidating = false
    @Published var validationMessage: String? = "Offline Premium Version"
    @Published private(set) var activationsLimit: Int = 0
    
    init() {
        // Always licensed for offline version
    }
    
    var canUseApp: Bool { true }
    
    func openPurchaseLink() {
        // No-op for offline version
    }
    
    func validateLicense() async {
        // Always valid for offline version
        validationMessage = "Offline Premium Version - All features unlocked"
    }
    
    func removeLicense() {
        // No-op for offline version
    }
}
