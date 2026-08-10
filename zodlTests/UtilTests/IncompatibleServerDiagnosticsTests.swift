//
//  IncompatibleServerDiagnosticsTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite struct ZcashErrorIncompatibleServerTests {
    private static let localBranch = ConsensusBranchID(bitPattern: 0xc8e7_1055)
    private static let remoteBranch = ConsensusBranchID(bitPattern: 0xc2d6_d0b4)

    @Test func wrongConsensusBranchIdIsIncompatibleServer() {
        let error = ZcashError.compactBlockProcessorWrongConsensusBranchId(
            Self.localBranch,
            Self.remoteBranch
        )

        #expect(error.code.rawValue == "ZCBPEO0011")
        #expect(error.isIncompatibleServer)
    }

    @Test func siblingServerValidationFailuresAreIncompatibleServer() {
        let errors: [ZcashError] = [
            .compactBlockProcessorNetworkMismatch(.mainnet, .testnet),
            .compactBlockProcessorSaplingActivationMismatch(419_200, 1),
            .compactBlockProcessorChainName("bogus"),
            .compactBlockProcessorConsensusBranchID
        ]

        for error in errors {
            #expect(error.isIncompatibleServer, "\(error.code.rawValue) should be an incompatible-server error")
        }
    }

    /// Branch IDs must use the fixed-width hexadecimal form used in ZIPs. In particular, values
    /// with the high bit set must not be printed as signed or sign-extended integers.
    @Test func consensusBranchIdRendersAsHex() {
        #expect(ConsensusBranchID(1_412_952_880).hexDescription == "0x5437f330")
        #expect(ConsensusBranchID(933_566_043).hexDescription == "0x37a5165b")
        #expect(ConsensusBranchID(bitPattern: 0xc2d6_d0b4).hexDescription == "0xc2d6d0b4")
    }

    @Test func incompatibleServerMessageNamesServerAndBranchIdsInHex() throws {
        let error = ZcashError.compactBlockProcessorWrongConsensusBranchId(
            ConsensusBranchID(1_412_952_880),
            ConsensusBranchID(933_566_043)
        )

        let message = try #require(
            withDependencies {
                $0.zcashSDKEnvironment.serverConfig = {
                    UserPreferencesStorage.ServerConfig(host: "outdated.example.com", port: 443, isCustom: false)
                }
            } operation: {
                error.incompatibleServerMessage
            }
        )

        #expect(message.contains("Server: outdated.example.com:443"))
        #expect(message.contains("Expected branch ID: 0x5437f330"))
        #expect(message.contains("Server's branch ID: 0x37a5165b"))
        #expect(message.contains("Error code: ZCBPEO0011"))
    }

    @Test func incompatibleServerMessageIsReadable() throws {
        let error = ZcashError.compactBlockProcessorWrongConsensusBranchId(
            ConsensusBranchID(1_412_952_880),
            ConsensusBranchID(933_566_043)
        )

        let message = try #require(
            withDependencies {
                $0.zcashSDKEnvironment.serverConfig = {
                    UserPreferencesStorage.ServerConfig(host: "outdated.example.com", port: 443, isCustom: false)
                }
            } operation: {
                error.incompatibleServerMessage
            }
        )

        let lines = message.components(separatedBy: "\n")
        #expect(lines.count == 7)
        #expect(lines[0].hasSuffix("."))
        #expect(lines[1].hasSuffix("."))
        #expect(message.contains("Zapp"))
        #expect(lines[2].isEmpty)
        #expect(lines[3].hasPrefix("Server: "))
        #expect(lines[6].hasPrefix("Error code: "))
        #expect(!message.contains("compactBlockProcessorWrongConsensusBranchId"))
        #expect(!message.contains("expecting This could be caused by"))
        #expect(!message.contains("1412952880"))
    }

    @Test func snapshotUsesTheWrittenMessageWithoutTheErrorPrefix() {
        let error = ZcashError.compactBlockProcessorWrongConsensusBranchId(
            ConsensusBranchID(1_412_952_880),
            ConsensusBranchID(933_566_043)
        )

        let (incompatible, generic, expected) = withDependencies {
            $0.zcashSDKEnvironment.serverConfig = {
                UserPreferencesStorage.ServerConfig(host: "outdated.example.com", port: 443, isCustom: false)
            }
        } operation: {
            (
                SyncStatusSnapshot.snapshotFor(state: .error(error)),
                SyncStatusSnapshot.snapshotFor(state: .error(ZcashError.compactBlockProcessorCritical)),
                error.incompatibleServerMessage
            )
        }

        #expect(incompatible.message == expected)
        #expect(!incompatible.message.hasPrefix("Error:"))
        #expect(generic.message.hasPrefix("Error:"))
        #expect(generic.message.contains("ZCBPEO0009"))
    }

    @Test func incompatibleServerMessageIsNilForUnrelatedErrors() {
        #expect(ZcashError.synchronizerNotPrepared.incompatibleServerMessage == nil)
        #expect(ZcashError.compactBlockProcessorCritical.incompatibleServerMessage == nil)
    }

    @Test func siblingFailureOmitsTheBranchIdLine() throws {
        let message = try #require(
            withDependencies {
                $0.zcashSDKEnvironment.serverConfig = {
                    UserPreferencesStorage.ServerConfig(host: "wrongnet.example.com", port: 443, isCustom: false)
                }
            } operation: {
                ZcashError.compactBlockProcessorNetworkMismatch(.mainnet, .testnet).incompatibleServerMessage
            }
        )

        #expect(message.contains("Server: wrongnet.example.com:443"))
        #expect(message.contains("Error code: ZCBPEO0012"))
        #expect(!message.contains("branch ID"))
        #expect(message.components(separatedBy: "\n").count == 5)
    }

    @Test func unrelatedErrorsAreNotIncompatibleServer() {
        let errors: [ZcashError] = [
            .synchronizerNotPrepared,
            .serviceGetInfoFailed(.timeOut),
            .compactBlockProcessorConnectionTimeout,
            .compactBlockProcessorCritical
        ]

        for error in errors {
            #expect(!error.isIncompatibleServer, "\(error.code.rawValue) should not be an incompatible-server error")
        }
    }
}
