//
//  SQLNotificationCenter.swift
//  SQLSwiftUIPackage Extensions
//
//  Lightweight notification bus for SQLite table change events.
//  Post after every write. Reactive stores subscribe to trigger re-fetch.
//

import Foundation

/// Lightweight notification bus for SQLite table change events.
/// Post after every write. Reactive stores subscribe to trigger re-fetch.
public final class SQLNotificationCenter: @unchecked Sendable {

    public static let shared = SQLNotificationCenter()
    private init() {}

    private let nc = NotificationCenter.default

    // MARK: — Notification Name

    static func notificationName(for table: String) -> Notification.Name {
        Notification.Name("SQLTableChanged_\(table)")
    }

    // MARK: — Posting

    /// Call this after every successful executeStatement or executeTransaction
    /// that modifies a table. Pass the exact table name string.
    public func post(tableChanged table: String) {
        nc.post(name: Self.notificationName(for: table), object: nil)
    }

    /// Post changes for multiple tables at once (e.g. after a transaction
    /// spanning WorkoutSession + CompletedSet)
    public func post(tablesChanged tables: [String]) {
        tables.forEach { post(tableChanged: $0) }
    }

    // MARK: — Subscribing

    /// Returns a publisher that fires whenever `table` changes.
    /// Use in SQLQueryStore to trigger re-fetch.
    public func publisher(for table: String) -> NotificationCenter.Publisher {
        nc.publisher(for: Self.notificationName(for: table))
    }
}
