import Foundation

/// Build settings come from Config/SpotlightSample.xcconfig and ignored Local.xcconfig.
enum SampleConfiguration {
    static let apiKey = value("MetabindAPIKey")
    static let organizationId = value("MetabindOrgId")
    static let projectId = value("MetabindProjectId")
    static let heroContentId = value("MetabindHeroContentId")
    static let infoContentId = value("MetabindInfoContentId")
    static let promotionContentId = value("MetabindPromotionContentId")

    private static func value(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
