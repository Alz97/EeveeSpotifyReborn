import Foundation

// MARK: - Constants
enum PremiumPlanConstants {
    static let planName = "EeveeSpotify"
    static let planIdentifier = "Eevee - WADBB Remod"
    static let colorCode = "#FFD2D7"
    static let featureColor = "#1ED760"
    
    enum SubscriptionStatus: Int {
        case trial = 0
        case prepaid = 1
        case subscription = 2
    }
    
    enum PlanVariant: Int {
        case standard = 2
    }
}

// MARK: - Error Handling
enum PremiumDataError: Error {
    case serializationFailed(String)
    case invalidData
}

// MARK: - Badge Configuration
struct PremiumBadgeConfig {
    let name: String
    let version: Int
    let colorCode: String
    
    static let `default` = PremiumBadgeConfig(
        name: PremiumPlanConstants.planIdentifier,
        version: 2,
        colorCode: PremiumPlanConstants.colorCode
    )
}

// MARK: - Service
final class PremiumPlanDataService {
    
    // MARK: - Public Methods
    
    func getPremiumPlanBadge(config: PremiumBadgeConfig = .default) throws -> Data {
        let badge = YourPremiumBadge.with {
            $0.name = config.name
            $0.version = config.version
            $0.colorCode = config.colorCode
        }
        
        return try serializeData(badge)
    }
    
    func getPremiumPlanRowData(originalPremiumPlanRow: PremiumPlanRow) throws -> Data {
        var premiumPlanRow = originalPremiumPlanRow
        
        premiumPlanRow.planName = PremiumPlanConstants.planName
        premiumPlanRow.planIdentifier = PremiumPlanConstants.planIdentifier
        premiumPlanRow.colorCode = PremiumPlanConstants.colorCode
        
        return try serializeData(premiumPlanRow)
    }
    
    func getPlanOverviewData(
        status: PremiumPlanConstants.SubscriptionStatus = .subscription,
        planVariant: PremiumPlanConstants.PlanVariant = .standard
    ) throws -> Data {
        let plan = createSpotifyPlan(status: status, planVariant: planVariant)
        return try serializeData(plan)
    }
    
    // MARK: - Private Methods
    
    private func createSpotifyPlan(
        status: PremiumPlanConstants.SubscriptionStatus,
        planVariant: PremiumPlanConstants.PlanVariant
    ) -> SpotifyPlan {
        return SpotifyPlan.with {
            $0.notice = createNotice(status: status)
            $0.subscription = createSubscriptionInfo(planVariant: planVariant)
        }
    }
    
    private func createNotice(status: PremiumPlanConstants.SubscriptionStatus) -> SpotifyPlan.Notice {
        return SpotifyPlan.Notice.with {
            $0.message = "payment_notice".localized
            $0.status = Int32(status.rawValue)
        }
    }
    
    private func createSubscriptionInfo(planVariant: PremiumPlanConstants.PlanVariant) -> SpotifyPlan.SubscriptionInfo {
        return SpotifyPlan.SubscriptionInfo.with {
            $0.planVariant = Int32(planVariant.rawValue)
            $0.planName = PremiumPlanConstants.planName
            $0.planCategory = PremiumPlanConstants.planIdentifier
            $0.colorCode = PremiumPlanConstants.colorCode
            $0.features = createFeatures()
        }
    }
    
    private func createFeatures() -> [SpotifyPlan.Feature] {
        return [
            createFeature(description: "ad_free_music_listening".localized),
            createFeature(description: "play_songs_in_any_order".localized),
            createFeature(description: "organize_listening_queue".localized)
        ]
    }
    
    private func createFeature(description: String) -> SpotifyPlan.Feature {
        return SpotifyPlan.Feature.with {
            $0.color = PremiumPlanConstants.featureColor
            $0.description_p = description
            $0.icon = SpotifyPlan.IconType.check
        }
    }
    
    private func serializeData<T>(_ object: T) throws -> Data {
        do {
            if let serializable = object as? Message {
                return try serializable.serializedData()
            } else {
                throw PremiumDataError.invalidData
            }
        } catch {
            throw PremiumDataError.serializationFailed("Failed to serialize data: \(error.localizedDescription)")
        }
    }
}

// MARK: - Convenience Extensions
extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
