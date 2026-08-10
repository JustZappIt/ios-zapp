import Foundation
import Testing
@testable import zodl_internal

@Suite struct IronwoodAnnouncementCopyTests {
    struct Entry: Sendable {
        let name: String
        let value: String
    }

    private static let entries = [
        Entry(name: "title", value: String(localizable: .ironwoodAnnouncementTitle)),
        Entry(name: "body1", value: String(localizable: .ironwoodAnnouncementBody1)),
        Entry(name: "body2", value: String(localizable: .ironwoodAnnouncementBody2)),
        Entry(name: "body3", value: String(localizable: .ironwoodAnnouncementBody3)),
        Entry(name: "guidePrefix", value: String(localizable: .ironwoodAnnouncementGuidePrefix)),
        Entry(name: "guideLink", value: String(localizable: .ironwoodAnnouncementGuideLink)),
        Entry(name: "guideSuffix", value: String(localizable: .ironwoodAnnouncementGuideSuffix)),
        Entry(name: "learnMore", value: String(localizable: .ironwoodAnnouncementLearnMore)),
        Entry(name: "continue", value: String(localizable: .ironwoodAnnouncementContinue))
    ]

    @Test(arguments: entries)
    func keyResolvesToNonEmptyTranslatedText(_ entry: Entry) {
        #expect(!entry.value.isEmpty)
        #expect(!entry.value.contains("ironwoodAnnouncement"))
    }

    @Test func guideSentenceConcatenatesToApprovedCopy() {
        let prefix = String(localizable: .ironwoodAnnouncementGuidePrefix)
        let link = String(localizable: .ironwoodAnnouncementGuideLink)
        let suffix = String(localizable: .ironwoodAnnouncementGuideSuffix)
        #expect(prefix + link + suffix == "If you'd rather not wait, our guide explains how to move funds manually.")
        #expect(prefix.hasSuffix(" "))
        #expect(suffix.hasPrefix(" "))
    }

    @Test func guideFragmentsKeepSpacesInEveryLanguage() throws {
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        #expect(localizations.contains("es"))
        for code in localizations {
            let bundle = try #require(Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)))
            let prefix = bundle.localizedString(forKey: "ironwoodAnnouncement.guidePrefix", value: nil, table: "Localizable")
            let suffix = bundle.localizedString(forKey: "ironwoodAnnouncement.guideSuffix", value: nil, table: "Localizable")
            #expect(prefix.hasSuffix(" "), "[\(code)] prefix lost its trailing space")
            #expect(suffix.hasPrefix(" "), "[\(code)] suffix lost its leading space")
        }
    }

    @Test func continueButtonUsesZappBranding() {
        #expect(String(localizable: .ironwoodAnnouncementContinue) == "Go to Zapp")
    }
}
