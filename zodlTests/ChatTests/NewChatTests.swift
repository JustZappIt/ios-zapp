//
//  NewChatTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
import ZappMessaging

@Suite(.serialized) struct NewChatTests {
    private static let peerKey = String(repeating: "b", count: PublicKeyRules.hexLength)
    private static let otherKey = String(repeating: "c", count: PublicKeyRules.hexLength)
    private static let ownKey = String(repeating: "a", count: PublicKeyRules.hexLength)

    @MainActor private func makeStore(
        myPublicKey: String = "",
        contacts: [ChatContact] = [],
        isCreating: Bool = false,
        dependencies: (inout DependencyValues) -> Void = { _ in }
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
        } withDependencies: {
            dependencies(&$0)
        }
    }

    private static func conversation(id: String, type: ConversationType, keys: [String]) -> ZMConversation {
        ZMConversation(id: id, type: type, participantIds: keys, displayName: id)
    }

    // MARK: - The docked primary action

    /// Android's dock: SCAN QR CODE until somebody is picked, START CHAT once a chip exists.
    /// A pasted key is offered on the detected-key row, and the dock starts the chat it names
    /// rather than reopening the scanner.
    @MainActor @Test func primaryActionOffersScanUntilAParticipantIsPicked() async {
        let store = makeStore()

        #expect(store.state.primaryAction == .scan)
        #expect(store.state.isPrimaryEnabled)

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }

        #expect(store.state.showsDetectedKey)
        #expect(store.state.primaryAction == .start)

        await store.send(.detectedKeyAdded) {
            $0.searchInput = ""
            $0.participants = [.init(publicKey: Self.peerKey, name: String(Self.peerKey.prefix(8)), displayName: nil)]
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
        #expect(!store.state.showsDetectedKey)
    }

    @MainActor @Test func primaryTappedForwardsToTheActionItAdvertises() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.primaryTapped)
        await store.receive(\.scanTapped)

        #expect(store.state.scan != nil)
    }

    /// Start chat with a key still in the field adds it and starts that chat.
    @MainActor @Test func startWithAPastedKeyAddsItAndStarts() async {
        let store = makeStore(dependencies: {
            $0.zappMessaging.hasLeftDirectConversation = { _ in false }
            $0.zappMessaging.createDirectConversation = { key, _ in
                Self.conversation(id: "dm", type: .direct, keys: [key])
            }
        })
        store.exhaustivity = .off

        await store.send(.peerKeyChanged(Self.peerKey))
        await store.send(.primaryTapped)
        await store.receive(\.startTapped)

        #expect(store.state.searchInput.isEmpty)
        #expect(store.state.isCreating || store.state.participants.isEmpty)
        await store.skipReceivedActions()
    }

    /// The group-name dialog shows a create failure from `errorCode`; an earlier error (our own
    /// key pasted into the field) must not greet it.
    @MainActor @Test func theGroupNameDialogOpensWithoutAnOlderError() async {
        let store = makeStore(
            myPublicKey: Self.ownKey,
            contacts: [
                ChatContact(publicKey: Self.peerKey, name: "Bea", address: "", isSaved: true),
                ChatContact(publicKey: Self.otherKey, name: "Cy", address: "", isSaved: true)
            ]
        )
        store.exhaustivity = .off

        await store.send(.contactTapped(ChatContact(publicKey: Self.peerKey, name: "Bea", address: "", isSaved: true)))
        await store.send(.contactTapped(ChatContact(publicKey: Self.otherKey, name: "Cy", address: "", isSaved: true)))
        await store.send(.peerKeyChanged(Self.ownKey))
        #expect(store.state.errorCode == .ownPublicKey)

        await store.send(.startTapped)

        #expect(store.state.isNamingGroup)
        #expect(store.state.errorCode == nil)
    }

    // MARK: - Participant chips

    /// Tapping a contact picks it rather than opening a DM straight away, and tapping it again
    /// drops it, as Android's `onContactToggle` does.
    @MainActor @Test func tappingAContactTogglesItsChip() async {
        let contact = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let store = makeStore(contacts: [contact])

        await store.send(.contactTapped(contact)) {
            $0.participants = [.init(publicKey: Self.peerKey, name: "Alice", displayName: "Alice")]
        }

        #expect(store.state.isSelected(contact))

        await store.send(.contactTapped(contact)) {
            $0.participants = []
        }
    }

    /// Add on the detected-key row makes a chip and clears the field without starting anything,
    /// so a second pasted key can join and Start chat asks for a group name.
    @MainActor @Test func pastedKeysAreAddedFromTheDetectedRowAndKeepTheGroupOpen() async {
        let store = makeStore()

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }
        #expect(store.state.canAddDetectedKey)

        await store.send(.detectedKeyAdded) {
            $0.searchInput = ""
            $0.participants = [.init(publicKey: Self.peerKey, name: String(Self.peerKey.prefix(8)), displayName: nil)]
        }
        #expect(!store.state.isCreating)

        await store.send(.peerKeyChanged(Self.otherKey)) {
            $0.searchInput = Self.otherKey
        }
        await store.send(.detectedKeyAdded) {
            $0.searchInput = ""
            $0.participants.append(
                .init(publicKey: Self.otherKey, name: String(Self.otherKey.prefix(8)), displayName: nil)
            )
        }

        // An added key is a chip, so pasting it again does not offer it a second time.
        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }
        #expect(!store.state.showsDetectedKey)
        #expect(store.state.participants.count == 2)

        await store.send(.startTapped) {
            $0.isNamingGroup = true
        }
    }

    @MainActor @Test func aPastedKeyOfASavedContactCarriesTheirName() async {
        let contact = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let store = makeStore(contacts: [contact])

        await store.send(.peerKeyChanged(Self.peerKey)) {
            $0.searchInput = Self.peerKey
        }
        await store.send(.detectedKeyAdded) {
            $0.searchInput = ""
            $0.participants = [.init(publicKey: Self.peerKey, name: "Alice", displayName: "Alice")]
        }
    }

    @MainActor @Test func ourOwnKeyCannotBecomeAChip() async {
        let store = makeStore(myPublicKey: Self.ownKey)

        await store.send(.peerKeyChanged(Self.ownKey)) {
            $0.searchInput = Self.ownKey
            $0.errorCode = .ownPublicKey
        }

        #expect(store.state.showsDetectedKey)
        #expect(!store.state.canAddDetectedKey)

        await store.send(.detectedKeyAdded)

        #expect(store.state.participants.isEmpty)
    }

    @MainActor @Test func oneChipStartsTheDirectChat() async {
        let created = LockIsolated<[(String, String?)]>([])
        let contact = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let direct = Self.conversation(id: "dm", type: .direct, keys: [Self.peerKey])
        let store = makeStore(contacts: [contact]) {
            $0.zappMessaging.hasLeftDirectConversation = { _ in false }
            $0.zappMessaging.createDirectConversation = { key, name in
                created.withValue { $0.append((key, name)) }
                return direct
            }
        }

        await store.send(.contactTapped(contact)) {
            $0.participants = [.init(publicKey: Self.peerKey, name: "Alice", displayName: "Alice")]
        }
        await store.send(.primaryTapped)
        await store.receive(\.startTapped) {
            $0.isCreating = true
        }
        await store.receive(\.created) {
            $0.isCreating = false
            $0.participants = []
        }

        #expect(created.value.map(\.0) == [Self.peerKey])
        #expect(created.value.map(\.1) == ["Alice"])
    }

    @MainActor @Test func aLeftDirectChatAsksBeforeRejoining() async {
        let contact = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let store = makeStore(contacts: [contact]) {
            $0.zappMessaging.hasLeftDirectConversation = { _ in true }
        }

        await store.send(.contactTapped(contact)) {
            $0.participants = [.init(publicKey: Self.peerKey, name: "Alice", displayName: "Alice")]
        }
        await store.send(.startTapped) {
            $0.isCreating = true
        }
        await store.receive(\.rejoinRequired) {
            $0.isCreating = false
            $0.alert = .rejoinDirect(name: "Alice", publicKey: Self.peerKey, displayName: "Alice")
        }
    }

    /// Two or more chips make a group, which Android names in a dialog before creating it.
    @MainActor @Test func twoChipsAskForAGroupNameThenCreateTheGroup() async {
        let createdGroups = LockIsolated<[(String, [String])]>([])
        let alice = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let carol = ChatContact(publicKey: Self.otherKey, name: "Carol", lastUpdated: .distantPast)
        let group = Self.conversation(id: "group", type: .group, keys: [Self.peerKey, Self.otherKey])
        let store = makeStore(contacts: [alice, carol]) {
            $0.zappMessaging.createGroup = { name, keys in
                createdGroups.withValue { $0.append((name, keys)) }
                return group
            }
        }

        await store.send(.contactTapped(alice)) {
            $0.participants = [.init(publicKey: Self.peerKey, name: "Alice", displayName: "Alice")]
        }
        await store.send(.contactTapped(carol)) {
            $0.participants.append(.init(publicKey: Self.otherKey, name: "Carol", displayName: "Carol"))
        }
        await store.send(.startTapped) {
            $0.isNamingGroup = true
        }

        #expect(!store.state.canConfirmGroup)

        await store.send(.groupConfirmTapped)
        await store.send(.groupNameChanged("Team")) {
            $0.groupName = "Team"
        }
        await store.send(.groupConfirmTapped) {
            $0.isCreating = true
        }
        await store.receive(\.created) {
            $0.isCreating = false
            $0.participants = []
            $0.groupName = ""
            $0.isNamingGroup = false
        }

        #expect(createdGroups.value.map(\.0) == ["Team"])
        #expect(createdGroups.value.map(\.1) == [[Self.peerKey, Self.otherKey]])
    }

    @MainActor @Test func aFailedGroupCreateKeepsTheNamingDialogUp() async {
        let alice = ChatContact(publicKey: Self.peerKey, name: "Alice", lastUpdated: .distantPast)
        let carol = ChatContact(publicKey: Self.otherKey, name: "Carol", lastUpdated: .distantPast)
        let store = makeStore(contacts: [alice, carol]) {
            $0.zappMessaging.createGroup = { _, _ in throw CancellationError() }
        }
        store.exhaustivity = .off

        await store.send(.contactTapped(alice))
        await store.send(.contactTapped(carol))
        await store.send(.startTapped)
        await store.send(.groupNameChanged("Team"))
        await store.send(.groupConfirmTapped)
        await store.receive(\.createFailed)

        #expect(store.state.isNamingGroup)
        #expect(store.state.groupName == "Team")
        #expect(store.state.errorCode != nil)
        #expect(!store.state.isCreating)

        await store.send(.groupCancelTapped)

        #expect(!store.state.isNamingGroup)
        #expect(store.state.groupName.isEmpty)
        #expect(store.state.participants.count == 2)
    }

    // MARK: - A pasted key is shown once, not twice

    @MainActor @Test func aCompleteKeyShowsTheDetectedKeyRow() async {
        let store = makeStore()

        await store.send(.peerKeyChanged("0x\(Self.peerKey.uppercased())")) {
            $0.searchInput = "0x\(Self.peerKey.uppercased())"
        }

        #expect(store.state.showsDetectedKey)
        #expect(store.state.canAddDetectedKey)
        #expect(store.state.detectedKey == Self.peerKey)
        #expect(store.state.participants.isEmpty)
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

    @MainActor @Test func clearingTheSearchEmptiesTheField() async {
        let store = makeStore()

        await store.send(.peerKeyChanged("bbbb")) {
            $0.searchInput = "bbbb"
        }

        await store.send(.searchCleared) {
            $0.searchInput = ""
        }

        #expect(store.state.primaryAction == .scan)
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
        #expect(store.state.showsDetectedKey)
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
        #expect(!store.state.showsDetectedKey)
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
}
