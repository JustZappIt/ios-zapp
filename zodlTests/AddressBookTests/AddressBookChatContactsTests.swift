//
//  AddressBookChatContactsTests.swift
//  zodlTests
//
//  Android keeps chat contacts in the wallet address book, so a chat contact with a ZEC address
//  is a Send recipient there. iOS merges them in at the picker without migrating storage.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) struct AddressBookChatContactsTests {
    private let bookAddress = "u1book"
    private let chatAddress = "u1chat"

    private func state(context: AddressBook.State.Context, isInSelectMode: Bool) -> AddressBook.State {
        var state = AddressBook.State()
        state.context = context
        state.isInSelectMode = isInSelectMode
        state.$addressBookContacts.withLock {
            $0 = AddressBookContacts(
                lastUpdated: .distantPast,
                version: AddressBookContacts.Constants.version,
                contacts: [Contact(address: bookAddress, name: "Book")]
            )
        }
        state.$chatContacts.withLock {
            $0 = ChatContacts(
                lastUpdated: .distantPast,
                version: ChatContacts.Constants.version,
                contacts: [
                    ChatContact(publicKey: String(repeating: "a", count: 64), name: "Chat", address: chatAddress),
                    // Same address as a book entry: the book entry stands.
                    ChatContact(publicKey: String(repeating: "b", count: 64), name: "Dupe", address: bookAddress),
                    // No address: nothing to send to.
                    ChatContact(publicKey: String(repeating: "c", count: 64), name: "Keyonly"),
                    // Block-only rows are not contacts.
                    ChatContact(
                        publicKey: String(repeating: "d", count: 64),
                        name: "Stranger",
                        address: "u1stranger",
                        isBlocked: true,
                        isSaved: false
                    )
                ]
            )
        }
        return state
    }

    @Test func theSendPickerOffersChatContactsWithAZecAddress() {
        withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            let contacts = state(context: .send, isInSelectMode: true).addressBookContactsToShow.contacts

            #expect(contacts.map(\.name) == ["Book", "Chat"])
            #expect(contacts.map(\.address) == [bookAddress, chatAddress])
        }
    }

    /// Managing the book is not picking: a chat contact is edited on the Contacts screen.
    @Test func theManagedBookShowsOnlyItsOwnRows() {
        withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            #expect(state(context: .settings, isInSelectMode: false).addressBookContactsToShow.contacts.map(\.name) == ["Book"])
            #expect(state(context: .swap, isInSelectMode: true).addressBookContactsToShow.contacts.isEmpty)
        }
    }
}
