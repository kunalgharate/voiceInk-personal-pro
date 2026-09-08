import Foundation

@MainActor
class LicenseViewModel: ObservableObject {
    static let shared = LicenseViewModel()
    
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var isDeactivating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0
    @Published private(set) var hasVerifiedLicense: Bool = true

    init() {
        licenseState = .licensed
    }

    func startTrial() -> Bool {
        // App is now free - always licensed
        return true
    }
    
    var canUseApp: Bool {
        return true
    }
    
    func openPurchaseLink() {
        // No purchase needed
    }
    
    func validateLicense(_ key: String? = nil) async {
        // No validation needed - app is free
        hasVerifiedLicense = true
    }
    
    func removeLicense() {
        // No license to remove
    }
    
    func deactivateLicense() async {
        // No license to deactivate
    }
    
    func refreshLicenseState() {
        // Always licensed
    }
    
    var usageRestrictionMessage: String? {
        return nil
    }
    
    var diagnosticLicenseStatus: String {
        return "Licensed (Personal Build)"
    }
}

// UserDefaults extension for compatibility
extension UserDefaults {
    var activationsLimit: Int {
        get { 0 }
        set { }
    }
}
