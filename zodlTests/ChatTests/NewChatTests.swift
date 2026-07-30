//
//  NewChatTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) struct NewChatTests {
    private static let peerKey = String(repeating: "b", count: PublicKeyRules.hexLength)
    private static let otherKey = String(repeating: "c", count: PublicKeyRules.hexLength)
    private static let ownKey = String(repeating: "a", count: PublicKeyRules.hexLength)

    @MainActor private func makeStore(
        myPublicKey: String = "",
        contacts: [ChatContact] = [],
        isCreating: Bool = false
    ) -> TestStoreOf<NewChat> {
        var state = NewChat.State()
        state.myPublicKey = myPublicKey
        state.isCreating = isCreating
        state.$chatContacts.withLock {
            $0 = ChatContacts(
                lastUpdated: .distantPast,
                version: ChatContacts.Constants.version,
                contacts: IdentifiedArrayOf(uniqueElements: contacts)
            )
        }

        return TestStore(initialState: state) {
            NewChat()
        }
    }

    // MARK: - The docked primary action

    @MainActor @Test func primaryActionOffersScanUntilThereIsSomethingToStart() async {
        let store = makeStore()

        #expect(store.state.primaryAction == .scan)
        #expect(store.state.isPrimaryEnabled)

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }

        #expect(store.state.primaryAction == .start)
        #expect(store.state.isPrimaryEnabled)
    }

    @MainActor @Test func partialKeyLeavesTheScanActionInPlace() async {
        let store = makeStore()

        await store.send(.peerKeyChanged("bbbb")) {
            $0.searchInput = "bbbb"
        }

        #expect(store.state.primaryAction == .scan)
        #expect(!store.state.showsRecipientCard)
    }

    @MainActor @Test func groupModeDrivesTheGroupActions() async {
        let contact = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let store = makeStore(contacts: [contact])

        await store.send(.newGroupTapped) {
            $0.isGroupMode = true
        }

        #expect(store.state.primaryAction == .createGroup)
        #expect(!store.state.isPrimaryEnabled)

        await store.send(.contactTapped(contact)) {
            $0.selectedContacts = [contact]
        }

        #expect(store.state.isPrimaryEnabled)

        await store.send(.groupCreateTapped) {
            $0.isNamingGroup = true
        }

        #expect(store.state.primaryAction == .confirmGroup)
        #expect(!store.state.isPrimaryEnabled)

        await store.send(.groupNameChanged("Team")) {
            $0.groupName = "Team"
        }

        #expect(store.state.isPrimaryEnabled)
    }

    @MainActor @Test func primaryTappedForwardsToTheActionItAdvertises() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.primaryTapped)
        await store.receive(\.scanTapped)

        #expect(store.state.scan != nil)
    }

    // MARK: - A pasted key is shown once, not twice

    @MainActor @Test func aCompleteKeyCollapsesTheSearchFieldIntoOneRecipientCard() async {
        let store = makeStore()

        await store.send(.peerKeyChanged("0x\(Self.peerKey.uppercased())")) {
            $0.searchInput = "0x\(Self.peerKey.uppercased())"
        }

        // The raw input is still held for editing, but the view swaps the field out for the
        // card, so the 64 characters are rendered exactly once.
        #expect(store.state.showsRecipientCard)
        #expect(store.state.detectedKey == Self.peerKey)
    }

    @Test func abbreviationKeepsBothEndsOfTheKey() {
        let abbreviated = PublicKeyRules.abbreviated(Self.peerKey)

        #expect(abbreviated.count < Self.peerKey.count)
        #expect(abbreviated.hasPrefix(String(Self.peerKey.prefix(12))))
        #expect(abbreviated.hasSuffix(String(Self.peerKey.suffix(6))))
    }

    @Test func shortKeysAreLeftAlone() {
        #expect(PublicKeyRules.abbreviated("abc") == "abc")
    }

    @MainActor @Test func clearingTheSearchDropsTheKeyAndTheTypedName() async {
        let store = makeStore()

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }

        await store.send(.displayNameChanged("Alice")) {
            $0.displayName = "Alice"
        }

        await store.send(.searchCleared) {
            $0.searchInput = ""
            $0.displayName = ""
        }

        #expect(!store.state.showsRecipientCard)
        #expect(store.state.primaryAction == .scan)
    }

    /// Otherwise a name typed for one key silently gets attached to the next key pasted.
    @MainActor @Test func swappingTheKeyDiscardsTheNameTypedForThePreviousOne() async {
        let store = makeStore()

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }

        await store.send(.displayNameChanged("Alice")) {
            $0.displayName = "Alice"
        }

        await store.send(.peerKeyChanged(Self.otherKey)) {
            $0.searchInput = Self.otherKey
            $0.displayName = ""
        }
    }

    @MainActor @Test func retypingTheSameKeyKeepsTheNameBeingTyped() async {
        let store = makeStore()

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }

        await store.send(.displayNameChanged("Alice")) {
            $0.displayName = "Alice"
        }

        // Trailing whitespace sanitizes to the same key, so the name has to survive.
        await store.send(.peerKeyChanged("\(Self.peerKey) ")) {
            $0.searchInput = "\(Self.peerKey) "
        }

        #expect(store.state.displayName == "Alice")
    }

    // MARK: - Scanning

    /// Asserted field by field rather than against a whole `Scan.State`: its `cancelId` is a
    /// fresh `UUID()` per instance, so an equality check could never match.
    @MainActor @Test func scanningPresentsAScannerRestrictedToPublicKeys() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.scanTapped)

        #expect(store.state.scan?.checkers == [.chatPublicKeyScanChecker])
        #expect(store.state.scan?.instructions == String(localizable: .newChatScanInstructions))
    }

    @MainActor @Test func aScannedKeyDismissesTheScannerAndBecomesTheRecipient() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.scanTapped)
        await store.send(.scan(.presented(.foundString(Self.peerKey))))
        await store.receive(\.peerKeyChanged)

        #expect(store.state.scan == nil)
        #expect(store.state.detectedKey == Self.peerKey)
        #expect(store.state.primaryAction == .start)
    }

    @MainActor @Test func cancellingTheScannerLeavesTheScreenUntouched() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.scanTapped)
        await store.send(.scan(.presented(.cancelTapped)))

        #expect(store.state.scan == nil)
        #expect(store.state.searchInput.isEmpty)
    }

    @MainActor @Test func theScannerIsNotOfferedWhileAConversationIsBeingCreated() async {
        let store = makeStore(isCreating: true)

        await store.send(.scanTapped)

        #expect(store.state.scan == nil)
    }

    // MARK: - Scan checker

    @Test func theCheckerAcceptsAKeyAndNormalizesIt() {
        let action = ChatPublicKeyScanChecker().checkQRCode("0X\(Self.peerKey.uppercased())")

        #expect(action == .foundString(Self.peerKey))
    }

    @Test func theCheckerRejectsAnythingThatIsNotAPublicKey() {
        let checker = ChatPublicKeyScanChecker()

        #expect(checker.checkQRCode("zcash:u1abcdef") == .scanFailed(.invalidPublicKey))
        #expect(checker.checkQRCode(String(repeating: "b", count: 63)) == .scanFailed(.invalidPublicKey))
        #expect(checker.checkQRCode("") == .scanFailed(.invalidPublicKey))
    }

    /// A key is recognised, never assembled. Dropping non-hex characters and truncating to 64
    /// turns ordinary text into a well-formed key for a peer who does not exist, so the whole
    /// payload has to be the key.
    @Test func payloadsThatMerelyContainHexAreNotKeys() {
        let checker = ChatPublicKeyScanChecker()
        let fabrications = [
            String(repeating: "g1", count: PublicKeyRules.hexLength),
            "https://example.com/tx/\(String(repeating: "deadbeef", count: 9))?ref=zz",
            "cafe babe deadbeef \(String(repeating: "feed", count: 20))",
            "\(String(repeating: "b", count: PublicKeyRules.hexLength))trailing-junk",
            "zcash:u1\(String(repeating: "a", count: PublicKeyRules.hexLength))"
        ]

        for payload in fabrications {
            #expect(PublicKeyRules.parse(payload) == nil, "should not parse: \(payload)")
            #expect(checker.checkQRCode(payload) == .scanFailed(.invalidPublicKey))
        }
    }

    /// Keys get copied out of wrapped displays, so whitespace anywhere is still forgiven.
    @Test func realKeysSurviveWrappingAndPrefixes() {
        let key = String(repeating: "b", count: PublicKeyRules.hexLength)

        #expect(PublicKeyRules.parse(key) == key)
        #expect(PublicKeyRules.parse("  \(key)\n") == key)
        #expect(PublicKeyRules.parse("0x\(key.uppercased())") == key)
        #expect(PublicKeyRules.parse("\(key.prefix(32))\n\(key.suffix(32))") == key)
    }

    @MainActor @Test func aSearchStringContainingHexDoesNotBecomeARecipient() async {
        let store = makeStore()
        let payload = "cafe babe deadbeef \(String(repeating: "feed", count: 20))"

        await store.send(.peerKeyChanged(payload)) {
            $0.searchInput = payload
        }

        #expect(!store.state.isValidKey)
        #expect(!store.state.showsRecipientCard)
        #expect(store.state.primaryAction == .scan)
    }

    // MARK: - Sharing our own key

    @MainActor @Test func ourOwnKeyCanBeSharedAsAScannableCode() async {
        let store = makeStore(myPublicKey: Self.ownKey)

        await store.send(.shareMyKeyTapped) {
            $0.isSharingMyKey = true
        }

        await store.send(.shareMyKeyDismissed) {
            $0.isSharingMyKey = false
        }
    }

    @MainActor @Test func thereIsNothingToShareBeforeAnIdentityExists() async {
        let store = makeStore()

        await store.send(.shareMyKeyTapped)

        #expect(!store.state.isSharingMyKey)
    }

    // MARK: - Empty state

    @MainActor @Test func theEmptyStateOnlyShowsWithNoContactsAndNoQuery() async {
        let store = makeStore()

        #expect(store.state.showsEmptyState)

        await store.send(.peerKeyChanged("a")) {
            $0.searchInput = "a"
        }

        #expect(!store.state.showsEmptyState)
    }

    @MainActor @Test func savedContactsReplaceTheEmptyState() {
        let store = makeStore(
            contacts: [ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)]
        )

        #expect(!store.state.showsEmptyState)
        #expect(store.state.visibleContacts.count == 1)
    }

    @MainActor @Test func ourOwnKeyIsNeverOfferedAName() async {
        let store = makeStore(myPublicKey: Self.ownKey)

        await store.send(.peerKeyChanged(Self.ownKey)) {
            $0.searchInput = Self.ownKey
            $0.errorCode = .ownPublicKey
        }

        #expect(store.state.isOwnKey)
        #expect(!store.state.showsNameField)
        #expect(!store.state.isPrimaryEnabled)
    }
}
