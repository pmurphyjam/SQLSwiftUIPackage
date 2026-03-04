//
//  SQLContainer.swift
//  SQLExtensions
//
//  Simplified container configuration for SQLSwiftUIPackage with App Group support.
//  Mirrors SwiftData's ModelContainer pattern for familiar, concise syntax.
//

import Foundation
import DataManager

/// Configuration for SQLSwiftUIPackage database setup.
/// Similar to SwiftData's ModelConfiguration but for SQLite.
public struct SQLConfiguration: Sendable {
    /// The name of the database file (e.g., "MySQL.db")
    public let databaseName: String
    
    /// Optional app group identifier for shared containers
    public let groupIdentifier: String?
    
    /// Whether to copy database from bundle if it doesn't exist
    public let copyFromBundle: Bool
    
    /// Initialize with database name and optional app group
    ///
    /// - Parameters:
    ///   - databaseName: Name of the SQLite database file (default: "SQLite.db")
    ///   - groupIdentifier: App Group identifier for shared containers (optional)
    ///   - copyFromBundle: Whether to copy database from bundle if missing (default: true)
    public init(
        databaseName: String = "SQLite.db",
        groupIdentifier: String? = nil,
        copyFromBundle: Bool = true
    ) {
        self.databaseName = databaseName
        self.groupIdentifier = groupIdentifier
        self.copyFromBundle = copyFromBundle
    }
}

/// A container that manages SQLSwiftUIPackage database configuration and lifecycle.
/// Provides a SwiftData-like API for easy setup with App Groups.
///
/// Example Usage:
/// ```swift
/// // Simple setup (Documents directory)
/// let container = try SQLContainer()
///
/// // App Group setup
/// let container = try SQLContainer(
///     configuration: SQLConfiguration(
///         databaseName: "MyApp.db",
///         groupIdentifier: "group.com.company.myapp"
///     )
/// )
/// ```
@MainActor
public final class SQLContainer {
    
    /// The configuration used to initialize this container
    public let configuration: SQLConfiguration
    
    /// The full path to the database file
    public let databasePath: String
    
    /// Whether the database connection is currently open
    public private(set) var isOpen: Bool = false
    
    // MARK: - Initialization
    
    /// Initialize a SQL container with the specified configuration
    ///
    /// - Parameter configuration: Database configuration (default uses SQLite.db in Documents)
    /// - Throws: SQLContainerError if setup fails
    public init(configuration: SQLConfiguration = SQLConfiguration()) throws {
        self.configuration = configuration
        
        // Determine database directory
        let containerDirectory: URL
        if let groupIdentifier = configuration.groupIdentifier {
            // Use app group container
            guard let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            ) else {
                throw SQLContainerError.invalidGroupIdentifier(groupIdentifier)
            }
            containerDirectory = groupURL
        } else {
            // Use Documents directory (default)
            guard let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw SQLContainerError.documentsDirectoryNotFound
            }
            containerDirectory = documentsURL
        }
        
        self.databasePath = containerDirectory
            .appendingPathComponent(configuration.databaseName)
            .path
        
        // Copy from bundle to target directory if needed
        if configuration.copyFromBundle {
            try copyDatabaseFromBundleIfNeeded(to: containerDirectory)
        }
        
        // Initialize DataManager
        DataManager.init()
        DataManager.setDBName(name: configuration.databaseName)
        
        // Open the connection (DataManager opens from Documents directory)
        // If using app group, the database must already be in Documents
        // or we need to copy it there
        if configuration.groupIdentifier != nil {
            try copyFromGroupToDocumentsIfNeeded(from: containerDirectory)
        }
        
        let opened = DataManager.openDBConnection()
        if !opened {
            throw SQLContainerError.failedToOpenConnection(databasePath)
        }
        
        self.isOpen = true
    }
    
    /// Convenience initializer with just a database name
    ///
    /// - Parameter databaseName: Name of the database file
    public convenience init(databaseName: String) throws {
        try self.init(configuration: SQLConfiguration(databaseName: databaseName))
    }
    
    /// Convenience initializer for app group containers
    ///
    /// - Parameters:
    ///   - databaseName: Name of the database file
    ///   - groupIdentifier: App Group identifier
    public convenience init(databaseName: String, groupIdentifier: String) throws {
        try self.init(
            configuration: SQLConfiguration(
                databaseName: databaseName,
                groupIdentifier: groupIdentifier
            )
        )
    }
    
    // MARK: - Database Operations
    
    /// Copy database from bundle to the target directory if it doesn't exist
    private func copyDatabaseFromBundleIfNeeded(to directory: URL) throws {
        let fileManager = FileManager.default
        let targetPath = directory.appendingPathComponent(configuration.databaseName).path
        
        // Check if database already exists
        guard !fileManager.fileExists(atPath: targetPath) else {
            return
        }
        
        // Find database in bundle
        let databaseNameWithoutExtension = (configuration.databaseName as NSString).deletingPathExtension
        let databaseExtension = (configuration.databaseName as NSString).pathExtension
        
        guard let bundlePath = Bundle.main.path(
            forResource: databaseNameWithoutExtension,
            ofType: databaseExtension
        ) else {
            // No database in bundle - will create new one
            return
        }
        
        // Copy to destination
        do {
            try fileManager.copyItem(atPath: bundlePath, toPath: targetPath)
        } catch {
            throw SQLContainerError.failedToCopyFromBundle(error)
        }
    }
    
    /// Copy database from group container to Documents directory
    /// DataManager expects the database in Documents, so we create a symlink or copy
    private func copyFromGroupToDocumentsIfNeeded(from groupDirectory: URL) throws {
        let fileManager = FileManager.default
        
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw SQLContainerError.documentsDirectoryNotFound
        }
        
        let sourcePath = groupDirectory.appendingPathComponent(configuration.databaseName).path
        let destPath = documentsURL.appendingPathComponent(configuration.databaseName).path
        
        // Remove existing file in Documents if present
        if fileManager.fileExists(atPath: destPath) {
            try? fileManager.removeItem(atPath: destPath)
        }
        
        // If source exists in group container, create symlink to it
        if fileManager.fileExists(atPath: sourcePath) {
            do {
                try fileManager.createSymbolicLink(atPath: destPath, withDestinationPath: sourcePath)
            } catch {
                // Symlink failed, try copying instead
                try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
            }
        }
    }
    
    /// Close the database connection
    public func close() {
        DataManager.closeDBConnection()
        isOpen = false
    }
    
    /// Delete the database file
    ///
    /// - Warning: This permanently deletes the database. Use with caution.
    public func deleteDatabase() throws {
        close()
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: databasePath) {
            try fileManager.removeItem(atPath: databasePath)
        }
    }
}

// MARK: - Errors

public enum SQLContainerError: LocalizedError {
    case invalidGroupIdentifier(String)
    case documentsDirectoryNotFound
    case failedToOpenConnection(String)
    case failedToCopyFromBundle(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidGroupIdentifier(let identifier):
            return "Invalid or inaccessible app group identifier: \(identifier). Ensure it's configured in your app's capabilities."
        case .documentsDirectoryNotFound:
            return "Could not locate Documents directory."
        case .failedToOpenConnection(let path):
            return "Failed to open database connection at path: \(path)"
        case .failedToCopyFromBundle(let error):
            return "Failed to copy database from bundle: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shared Container Access

extension SQLContainer {
    
    /// Shared container instance for singleton pattern (optional)
    nonisolated(unsafe) private static var _shared: SQLContainer?
    
    /// Access a shared container instance
    ///
    /// Must call `setupShared(configuration:)` before accessing
    public static var shared: SQLContainer {
        get async {
            await MainActor.run {
                guard let container = _shared else {
                    fatalError("SQLContainer.shared accessed before setupShared() was called")
                }
                return container
            }
        }
    }
    
    /// Setup the shared container instance
    ///
    /// - Parameter configuration: Database configuration
    /// - Throws: SQLContainerError if setup fails
    @MainActor
    public static func setupShared(configuration: SQLConfiguration = SQLConfiguration()) throws {
        _shared = try SQLContainer(configuration: configuration)
    }
    
    /// Setup the shared container for an app group
    ///
    /// - Parameters:
    ///   - databaseName: Name of the database file
    ///   - groupIdentifier: App Group identifier
    @MainActor
    public static func setupShared(databaseName: String, groupIdentifier: String) throws {
        _shared = try SQLContainer(databaseName: databaseName, groupIdentifier: groupIdentifier)
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

/// Environment key for SQLContainer
private struct SQLContainerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: SQLContainer? = nil
}

extension EnvironmentValues {
    /// Access SQLContainer from SwiftUI environment
    public var sqlContainer: SQLContainer? {
        get { self[SQLContainerKey.self] }
        set { self[SQLContainerKey.self] = newValue }
    }
}

extension View {
    /// Inject SQLContainer into the SwiftUI environment
    ///
    /// - Parameter container: The SQLContainer to inject
    /// - Returns: Modified view with container in environment
    public func sqlContainer(_ container: SQLContainer) -> some View {
        environment(\.sqlContainer, container)
    }
}
