//
//  SQLSelectQuery.swift
//  SQLSwiftUIPackage Extensions
//
//  Fluent SELECT query builder for SQLSwiftUIPackage / SQLDataAccess.
//  Use .build() to get (sql: String, params: [Any]) for getRecordsForQuery.
//

import Foundation
import DataManager

// MARK: — Condition Operators

public enum SQLOperator: String, Sendable {
    case equals        = "="
    case notEquals     = "!="
    case lessThan      = "<"
    case greaterThan   = ">"
    case lessThanOrEq  = "<="
    case greaterThanOrEq = ">="
    case like          = "LIKE"
    case notLike       = "NOT LIKE"
    case isNull        = "IS NULL"
    case isNotNull     = "IS NOT NULL"
    case `in`          = "IN"
}

public enum SQLSortOrder: String, Sendable {
    case ascending  = "ASC"
    case descending = "DESC"
}

// MARK: — SQLSelectQuery

/// Fluent SELECT query builder for SQLSwiftUIPackage / SQLDataAccess.
/// Use .build() to get (sql: String, params: [Any]) for getRecordsForQuery.
///
/// Example:
///   let (sql, params) = SQLSelectQuery("Exercise")
///       .where("muscleGroup", .equals, "Chest")
///       .where("equipment", .in, ["Barbell", "Dumbbell"])
///       .orderBy("name", .ascending)
///       .limit(20)
///       .build()
///
public struct SQLSelectQuery: @unchecked Sendable {

    private let table: String
    private var columns: [String] = ["*"]
    private var conditions: [(column: String, op: SQLOperator, value: Any?)] = []
    private var orConditions: [(column: String, op: SQLOperator, value: Any?)] = []
    private var ordering: [(column: String, order: SQLSortOrder)] = []
    private var limitValue: Int? = nil
    private var offsetValue: Int? = nil
    private var joins: [String] = []

    public init(_ table: String) {
        self.table = table
    }

    // MARK: — Columns

    /// SELECT only specific columns instead of *
    public func select(_ columns: String...) -> Self {
        var copy = self
        copy.columns = columns
        return copy
    }

    // MARK: — WHERE (AND)

    public func `where`(_ column: String, _ op: SQLOperator, _ value: Any) -> Self {
        var copy = self
        copy.conditions.append((column, op, value))
        return copy
    }

    public func whereNull(_ column: String) -> Self {
        var copy = self
        copy.conditions.append((column, .isNull, nil))
        return copy
    }

    public func whereNotNull(_ column: String) -> Self {
        var copy = self
        copy.conditions.append((column, .isNotNull, nil))
        return copy
    }

    // MARK: — WHERE OR

    public func orWhere(_ column: String, _ op: SQLOperator, _ value: Any) -> Self {
        var copy = self
        copy.orConditions.append((column, op, value))
        return copy
    }

    // MARK: — ORDER BY

    public func orderBy(_ column: String, _ order: SQLSortOrder = .ascending) -> Self {
        var copy = self
        copy.ordering.append((column, order))
        return copy
    }

    // MARK: — LIMIT / OFFSET

    public func limit(_ n: Int) -> Self {
        var copy = self
        copy.limitValue = n
        return copy
    }

    public func offset(_ n: Int) -> Self {
        var copy = self
        copy.offsetValue = n
        return copy
    }

    // MARK: — JOIN

    /// Raw JOIN clause. e.g. "INNER JOIN CompletedSet ON CompletedSet.sessionId = WorkoutSession.id"
    public func join(_ clause: String) -> Self {
        var copy = self
        copy.joins.append(clause)
        return copy
    }

    // MARK: — Build

    /// Returns (sql, params) ready for DataManager.dataAccess.getRecordsForQuery
    public func build() -> (sql: String, params: [Any]) {
        var params: [Any] = []
        var sql = "SELECT \(columns.joined(separator: ", ")) FROM \(table)"

        // JOINs
        if !joins.isEmpty {
            sql += " " + joins.joined(separator: " ")
        }

        // WHERE
        var clauses: [String] = []

        for cond in conditions {
            switch cond.op {
            case .isNull:
                clauses.append("\(cond.column) IS NULL")
            case .isNotNull:
                clauses.append("\(cond.column) IS NOT NULL")
            case .in:
                if let arr = cond.value as? [Any] {
                    let placeholders = Array(repeating: "?", count: arr.count).joined(separator: ",")
                    clauses.append("\(cond.column) IN (\(placeholders))")
                    params.append(contentsOf: arr)
                }
            default:
                clauses.append("\(cond.column) \(cond.op.rawValue) ?")
                if let v = cond.value { params.append(v) }
            }
        }

        // OR conditions (grouped: AND (a OR b OR c))
        if !orConditions.isEmpty {
            let orClauses = orConditions.map { "\($0.column) \($0.op.rawValue) ?" }
            clauses.append("(" + orClauses.joined(separator: " OR ") + ")")
            orConditions.forEach { if let v = $0.value { params.append(v) } }
        }

        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }

        // ORDER BY
        if !ordering.isEmpty {
            let orderClauses = ordering.map { "\($0.column) \($0.order.rawValue)" }
            sql += " ORDER BY " + orderClauses.joined(separator: ", ")
        }

        // LIMIT / OFFSET
        if let limit = limitValue {
            sql += " LIMIT \(limit)"
        }
        if let offset = offsetValue {
            sql += " OFFSET \(offset)"
        }

        return (sql, params)
    }

    // MARK: — Execute (convenience)

    /// Executes the query immediately and returns raw [[String:Any]]
    public func execute() -> [[String: Any]] {
        let (sql, params) = build()
        return DataManager.dataAccess.getRecordsForQuery(sql, withParams: params) as? [[String: Any]] ?? []
    }
}
