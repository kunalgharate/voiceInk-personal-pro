import Foundation

protocol LicenseViewModelProtocol: ObservableObject {
    associatedtype LicenseStateType: Equatable
    
    var licenseState: LicenseStateType { get }
    var licenseKey: String { get set }
    var isValidating: Bool { get set }
    var validationMessage: String? { get set }
    var canUseApp: Bool { get }
    
    func openPurchaseLink()
    func validateLicense() async
    func removeLicense()
}

// Extend both license view models to conform to protocol
extension LicenseViewModel: LicenseViewModelProtocol {
    typealias LicenseStateType = LicenseState
}

extension OfflineLicenseViewModel: LicenseViewModelProtocol {
    typealias LicenseStateType = LicenseState
}
