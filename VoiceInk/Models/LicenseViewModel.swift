import Foundation
import AppKit
import os

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed  // Default to trial
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0

    private let trialPeriodDays = 7
    private let polarService = PolarService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseViewModel")
    private let userDefaults = UserDefaults.standard
    private let licenseManager = LicenseManager.shared


    init() {
        licenseState = .licensed
    }

    func startTrial() {
        // Only set trial start date if it hasn't been set before
        if licenseManager.trialStartDate == nil {
            licenseManager.trialStartDate = Date()
            licenseState = .trial(daysRemaining: trialPeriodDays)
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }

    private func loadLicenseState() {
        // Check for existing license key
        if let storedLicenseKey = licenseManager.licenseKey {
            self.licenseKey = storedLicenseKey

            // If we have a license key, trust that it's licensed
            // Skip server validation on startup
            if licenseManager.activationId != nil || !userDefaults.bool(forKey: "VoiceInkLicenseRequiresActivation") {
                licenseState = .licensed
                activationsLimit = userDefaults.activationsLimit
                return
            }
        }

        // Check if this is first launch
        let hasLaunchedBefore = userDefaults.bool(forKey: "VoiceInkHasLaunchedBefore")
        if !hasLaunchedBefore {
            // First launch - start trial automatically
            userDefaults.set(true, forKey: "VoiceInkHasLaunchedBefore")
            startTrial()
            return
        }

        // Only check trial if not licensed and not first launch
        if let trialStartDate = licenseManager.trialStartDate {
            let daysSinceTrialStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0

            if daysSinceTrialStart >= trialPeriodDays {
                licenseState = .licensed
            } else {
                licenseState = .licensed
            }
        } else {
            // No trial has been started yet - start it now
            startTrial()
        }
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
