//
//  SQLQueryDecoder.swift
//  SQLSwiftUIPackage Extensions
//
//  Decodes [[String: Any]] results from SQLDataAccess into typed Swift models.
//

import Foundation
import DataManager

/// Decodes [[String: Any]] results from SQLDataAccess into typed Swift models.
/// Each model must implement SQLDecodable (see below).
public protocol SQLDecodable {
    /// Map a single row dictionary from SQLDataAccess to Self.
    /// Return nil to skip malformed rows.
    static func decode(row: [String: Any]) -> Self?
}

extension SQLSelectQuery {

    /// Execute and decode results into [T] where T implements SQLDecodable.
    public func decode<T: SQLDecodable>(_ type: T.Type) -> [T] {
        execute().compactMap { T.decode(row: $0) }
    }
}

// MARK: — Convenience static execute

/// Execute any raw SQL string and decode to [T]
public func sqlFetch<T: SQLDecodable>(_ type: T.Type, sql: String, params: [Any] = []) -> [T] {
    let rows = DataManager.dataAccess.getRecordsForQuery(sql, withParams: params) as? [[String: Any]] ?? []
    return rows.compactMap { T.decode(row: $0) }
}
