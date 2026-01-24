import Foundation

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0

    init() {
        licenseState = .licensed
    }

    func startTrial() {
        // App is now free - always licensed
    }
    
    var canUseApp: Bool {
        return true
    }
    
    func openPurchaseLink() {
        // No purchase needed
    }
    
    func validateLicense() async {
        // No validation needed - app is free
    }
    
    func removeLicense() {
        // No license to remove
    }
}

// UserDefaults extension for compatibility
extension UserDefaults {
    var activationsLimit: Int {
        get { 0 }
        set { }
    }
}
