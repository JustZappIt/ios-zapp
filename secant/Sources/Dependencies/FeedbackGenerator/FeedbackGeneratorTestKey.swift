//
//  FeedbackGeneratorTestKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 14.11.2022.
//

import ComposableArchitecture
import IssueReporting

extension FeedbackGeneratorClient {
    static let noOp = Self(
        generateSuccessFeedback: { },
        generateWarningFeedback: { },
        generateErrorFeedback: { }
    )
}
