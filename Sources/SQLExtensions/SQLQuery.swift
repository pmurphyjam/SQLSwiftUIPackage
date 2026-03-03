//
//  SQLQuery.swift
//  SQLSwiftUIPackage Extensions
//
//  SwiftUI property wrapper for reactive SQLSwiftUIPackage queries.
//  Automatically updates the view when watched tables change.
//

import SwiftUI
import Observation

/// SwiftUI property wrapper for reactive SQLSwiftUIPackage queries.
/// Automatically updates the view when watched tables change.
///
/// Usage in a View:
///   @SQLQuery(
///       query: SQLSelectQuery("Exercise")
///           .where("category", .equals, "Chest")
///           .orderBy("name"),
///       type: Exercise.self,
///       watch: ["Exercise"]
///   ) var exercises
///
///   // In body: exercises.results, exercises.isLoading
///
@propertyWrapper
@MainActor
public struct SQLQuery<T: SQLDecodable>: DynamicProperty {

    @State private var store: SQLQueryStore<T>

    public init(query: SQLSelectQuery, type: T.Type, watch tables: [String]) {
        _store = State(initialValue: SQLQueryStore(query: query, type: type, watchTables: tables))
    }

    public var wrappedValue: SQLQueryStore<T> {
        store
    }

    /// Convenience access: $exercises gives the store, exercises.results gives [T]
    public var projectedValue: Binding<SQLQueryStore<T>> {
        $store
    }
}
