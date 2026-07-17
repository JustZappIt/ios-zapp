//
//  RemoteStorageLiveKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-27-2024.
//

import Foundation
import ComposableArchitecture

extension RemoteStorageClient: DependencyKey {
    enum RemoteStorageError: Error {
        case containerURL
        case fileDoesntExist
    }
    
    static let liveValue: RemoteStorageClient = Self.live()
    
    static func live() -> Self {
        return Self(
            loadDataFromFile: { filename in
                let fileManager = FileManager.default

                guard let containerURL = path(fileManager, filename: filename) else {
                    throw RemoteStorageError.containerURL
                }

                guard fileManager.fileExists(atPath: containerURL.path) else {
                    throw RemoteStorageError.fileDoesntExist
                }

                return try Data(contentsOf: containerURL)
            },
            storeDataToFile: { data, filename in
                let fileManager = FileManager.default

                guard let containerURL = path(fileManager, filename: filename) else {
                    throw RemoteStorageError.containerURL
                }

                try data.write(to: containerURL)
            },
            removeFile: { filename in
                let fileManager = FileManager.default

                guard let containerURL = path(fileManager, filename: filename) else {
                    throw RemoteStorageError.containerURL
                }

                try fileManager.removeItem(at: containerURL)
            }
        )
    }
    
    private static func path(_ fileManager: FileManager, filename: String) -> URL? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }

        return fileManager.url(
            forUbiquityContainerIdentifier: "iCloud.\(bundleIdentifier)"
        )?.appendingPathComponent("Documents").appendingPathComponent(filename)
    }
}
