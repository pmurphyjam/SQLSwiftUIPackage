//
//  SQLQueryStore.swift
//  SQLSwiftUIPackage Extensions
//
//  An @Observable store that holds live results for a SQLSelectQuery.
//  Re-executes the query whenever any watched table posts a change notification.
//

import Foundation
import Observation
import Combine

/// An @Observable store that holds live results for a SQLSelectQuery.
/// Re-executes the query whenever any watched table posts a change notification.
///
/// Usage in a ViewModel:
///   let exerciseStore = SQLQueryStore(
///       query: SQLSelectQuery("Exercise").orderBy("name"),
///       type: Exercise.self,
///       watchTables: ["Exercise"]
///   )
///
@Observable
@MainActor
public final class SQLQueryStore<T: SQLDecodable> {

    // MARK: — Public State

    public private(set) var results: [T] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: String? = nil

    // MARK: — Private

    private var query: SQLSelectQuery
    private var watchTables: [String]
    private var cancellables = Set<AnyCancellable>()

    // MARK: — Init

    public init(query: SQLSelectQuery, type: T.Type, watchTables: [String]) {
        self.query = query
        self.watchTables = watchTables
        subscribeToChanges()
        fetch()
    }

    // MARK: — Query Update

    /// Replace the query (e.g. when filter changes) and immediately re-fetch.
    public func update(query: SQLSelectQuery) {
        self.query = query
        fetch()
    }

    // MARK: — Fetch

    public func fetch() {
        isLoading = true
        error = nil
        let fetched = query.decode(T.self)
        results = fetched
        isLoading = false
    }

    // MARK: — Observation

    private func subscribeToChanges() {
        for table in watchTables {
            SQLNotificationCenter.shared
                .publisher(for: table)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.fetch()
                }
                .store(in: &cancellables)
        }
    }
}
