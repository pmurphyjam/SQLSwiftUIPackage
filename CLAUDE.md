# CLAUDE.md — SQLSwiftUIPackage Extensions
## Reactive SELECT Queries · Type-Safe Query Builder · Swift Observation

---

## Project Goal

Extend **pmurphyjam/SQLSwiftUIPackage** (SQLDataAccess + DataManager + Sqldb) with three missing capabilities without replacing or modifying the package itself:

1. **Type-Safe SELECT Query Builder** — fluent `.where().orderBy().limit()` API that mirrors what `Sqldb` already does for insert/update/upsert, but for SELECT
2. **Reactive SELECT Queries** — queries that automatically re-execute and publish new results when underlying data changes
3. **Swift Observation** — `@Observable` ViewModels and a SwiftUI `@Query`-equivalent property wrapper backed by SQLSwiftUIPackage

All code is written as **Swift extensions and wrapper types** in the Fitamatic target. Do NOT fork or modify the SQLSwiftUIPackage source.

---

## What SQLSwiftUIPackage Already Does (Do Not Re-Implement)

```swift
// SQLDataAccess — raw query execution
DataManager.dataAccess.getRecordsForQuery("select * from Exercise", withParams: [])
// → [[String: Any]]

DataManager.dataAccess.executeStatement(sql, withParams: params)
// → Bool

DataManager.dataAccess.executeTransaction(sqlAndParamsArray)
// → Bool

// Sqldb protocol — auto-generates SQL for writes
struct Exercise: Codable, Sqldb, Mappable {
    var tableName: String? = "Exercise"
    var id: Int? = 0
    var name: String? = ""
    // ...
}
let sqlParams = exercise.getSQLInsert()
let sqlParams = exercise.getSQLUpdateValid(whereItems: "id")
let sqlParams = exercise.getSQLUpsertValid(whereItems: "id", forId: "id")
```

`Sqldb` covers all writes. The gap is entirely on the **read side**.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   SwiftUI Views                     │
│  @SQLQuery var exercises: [Exercise]                │
│  @SQLQuery var workouts: [WorkoutSession]           │
└────────────────┬────────────────────────────────────┘
                 │ auto-updates via @Observable
┌────────────────▼────────────────────────────────────┐
│              SQLQueryStore<T> (@Observable)          │
│  - holds current results: [T]                       │
│  - subscribes to SQLNotificationCenter              │
│  - re-executes query on table change                │
└────────────────┬────────────────────────────────────┘
                 │ executes
┌────────────────▼────────────────────────────────────┐
│              SQLSelectQuery<T>                      │
│  - type-safe fluent builder                         │
│  - builds SQL string + params                       │
│  - decodes [[String:Any]] → [T]                     │
└────────────────┬────────────────────────────────────┘
                 │ calls
┌────────────────▼────────────────────────────────────┐
│   DataManager.dataAccess.getRecordsForQuery(...)    │
│              (SQLSwiftUIPackage — unchanged)               │
└─────────────────────────────────────────────────────┘
                 ▲
┌────────────────┴────────────────────────────────────┐
│           SQLNotificationCenter                     │
│  - .post(tableChanged: "Exercise")                  │
│  - called by every write helper after executeStatement│
└─────────────────────────────────────────────────────┘
```

---

## File Structure

```
Fitamatic/
├── DB/
│   ├── Extensions/
│   │   ├── SQLSelectQuery.swift          ← Type-safe SELECT builder
│   │   ├── SQLQueryDecoder.swift         ← [[String:Any]] → Codable decoder
│   │   ├── SQLNotificationCenter.swift   ← Change notification bus
│   │   ├── SQLQueryStore.swift           ← @Observable reactive store
│   │   └── SQLQuery.swift               ← @SQLQuery property wrapper
│   └── Models/
│       ├── Exercise+SQL.swift
│       ├── WorkoutSession+SQL.swift
│       └── ...
```

---

## 1. SQLNotificationCenter

**File:** `DB/Extensions/SQLNotificationCenter.swift`

This is the event bus. Every write (insert/update/upsert/delete) posts a notification naming which table changed. Reactive stores subscribe to these and re-run their queries.

```swift
import Foundation

/// Lightweight notification bus for SQLite table change events.
/// Post after every write. Reactive stores subscribe to trigger re-fetch.
final class SQLNotificationCenter {

    static let shared = SQLNotificationCenter()
    private init() {}

    private let nc = NotificationCenter.default

    // MARK: — Notification Name

    static func notificationName(for table: String) -> Notification.Name {
        Notification.Name("SQLTableChanged_\(table)")
    }

    // MARK: — Posting

    /// Call this after every successful executeStatement or executeTransaction
    /// that modifies a table. Pass the exact table name string.
    func post(tableChanged table: String) {
        nc.post(name: Self.notificationName(for: table), object: nil)
    }

    /// Post changes for multiple tables at once (e.g. after a transaction
    /// spanning WorkoutSession + CompletedSet)
    func post(tablesChanged tables: [String]) {
        tables.forEach { post(tableChanged: $0) }
    }

    // MARK: — Subscribing

    /// Returns a publisher that fires whenever `table` changes.
    /// Use in SQLQueryStore to trigger re-fetch.
    func publisher(for table: String) -> NotificationCenter.Publisher {
        nc.publisher(for: Self.notificationName(for: table))
    }
}
```

**Usage in write helpers (Models layer):**

```swift
// In Exercise+SQL.swift, after every successful write:
@discardableResult
static func insertExercise(_ obj: Exercise) -> Bool {
    let sqlParams = obj.getSQLInsert()
    let status = DataManager.dataAccess.executeStatement(
        sqlParams[SQL] as! String,
        withParams: sqlParams[PARAMS] as! [Any]
    )
    if status {
        SQLNotificationCenter.shared.post(tableChanged: "Exercise")
    }
    return status
}
```

---

## 2. SQLSelectQuery — Type-Safe SELECT Builder

**File:** `DB/Extensions/SQLSelectQuery.swift`

Mirrors the fluent style of `Sqldb` but for SELECT. Builds a SQL string + params array that feeds directly into `DataManager.dataAccess.getRecordsForQuery`.

```swift
import Foundation

// MARK: — Condition Operators

enum SQLOperator: String {
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

enum SQLSortOrder: String {
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
struct SQLSelectQuery {

    private let table: String
    private var columns: [String] = ["*"]
    private var conditions: [(column: String, op: SQLOperator, value: Any?)] = []
    private var orConditions: [(column: String, op: SQLOperator, value: Any?)] = []
    private var ordering: [(column: String, order: SQLSortOrder)] = []
    private var limitValue: Int? = nil
    private var offsetValue: Int? = nil
    private var joins: [String] = []

    init(_ table: String) {
        self.table = table
    }

    // MARK: — Columns

    /// SELECT only specific columns instead of *
    func select(_ columns: String...) -> Self {
        var copy = self
        copy.columns = columns
        return copy
    }

    // MARK: — WHERE (AND)

    func `where`(_ column: String, _ op: SQLOperator, _ value: Any) -> Self {
        var copy = self
        copy.conditions.append((column, op, value))
        return copy
    }

    func whereNull(_ column: String) -> Self {
        var copy = self
        copy.conditions.append((column, .isNull, nil))
        return copy
    }

    func whereNotNull(_ column: String) -> Self {
        var copy = self
        copy.conditions.append((column, .isNotNull, nil))
        return copy
    }

    // MARK: — WHERE OR

    func orWhere(_ column: String, _ op: SQLOperator, _ value: Any) -> Self {
        var copy = self
        copy.orConditions.append((column, op, value))
        return copy
    }

    // MARK: — ORDER BY

    func orderBy(_ column: String, _ order: SQLSortOrder = .ascending) -> Self {
        var copy = self
        copy.ordering.append((column, order))
        return copy
    }

    // MARK: — LIMIT / OFFSET

    func limit(_ n: Int) -> Self {
        var copy = self
        copy.limitValue = n
        return copy
    }

    func offset(_ n: Int) -> Self {
        var copy = self
        copy.offsetValue = n
        return copy
    }

    // MARK: — JOIN

    /// Raw JOIN clause. e.g. "INNER JOIN CompletedSet ON CompletedSet.sessionId = WorkoutSession.id"
    func join(_ clause: String) -> Self {
        var copy = self
        copy.joins.append(clause)
        return copy
    }

    // MARK: — Build

    /// Returns (sql, params) ready for DataManager.dataAccess.getRecordsForQuery
    func build() -> (sql: String, params: [Any]) {
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
    func execute() -> [[String: Any]] {
        let (sql, params) = build()
        return DataManager.dataAccess.getRecordsForQuery(sql, withParams: params) as? [[String: Any]] ?? []
    }
}
```

---

## 3. SQLQueryDecoder — `[[String:Any]]` → Codable

**File:** `DB/Extensions/SQLQueryDecoder.swift`

SQLDataAccess returns `[[String: Any]]`. This decoder maps those dictionaries to typed Swift structs using each model's `dbDecode` method (the ObjectMapper pattern already used in SQLSwiftUIPackage).

```swift
import Foundation

/// Decodes [[String: Any]] results from SQLDataAccess into typed Swift models.
/// Each model must implement SQLDecodable (see below).
protocol SQLDecodable {
    /// Map a single row dictionary from SQLDataAccess to Self.
    /// Return nil to skip malformed rows.
    static func decode(row: [String: Any]) -> Self?
}

extension SQLSelectQuery {

    /// Execute and decode results into [T] where T implements SQLDecodable.
    func decode<T: SQLDecodable>(_ type: T.Type) -> [T] {
        execute().compactMap { T.decode(row: $0) }
    }
}

// MARK: — Convenience static execute

/// Execute any raw SQL string and decode to [T]
func sqlFetch<T: SQLDecodable>(_ type: T.Type, sql: String, params: [Any] = []) -> [T] {
    let rows = DataManager.dataAccess.getRecordsForQuery(sql, withParams: params) as? [[String: Any]] ?? []
    return rows.compactMap { T.decode(row: $0) }
}
```

**Implementation pattern for each model:**

```swift
// In Exercise+SQL.swift
extension Exercise: SQLDecodable {
    static func decode(row: [String: Any]) -> Exercise? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String else { return nil }
        return Exercise(
            id: id,
            name: name,
            category: row["category"] as? String ?? "",
            primaryMuscle: row["primaryMuscle"] as? String ?? "",
            equipment: row["equipment"] as? String ?? "",
            difficulty: row["difficulty"] as? String ?? "",
            instructions: row["instructions"] as? String ?? ""
        )
    }
}
```

---

## 4. SQLQueryStore — @Observable Reactive Store

**File:** `DB/Extensions/SQLQueryStore.swift`

`@Observable` class that holds results for one query. Subscribes to `SQLNotificationCenter` for the relevant tables and re-executes the query automatically on any change.

```swift
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
final class SQLQueryStore<T: SQLDecodable> {

    // MARK: — Public State

    private(set) var results: [T] = []
    private(set) var isLoading: Bool = false
    private(set) var error: String? = nil

    // MARK: — Private

    private var query: SQLSelectQuery
    private var watchTables: [String]
    private var cancellables = Set<AnyCancellable>()

    // MARK: — Init

    init(query: SQLSelectQuery, type: T.Type, watchTables: [String]) {
        self.query = query
        self.watchTables = watchTables
        subscribeToChanges()
        fetch()
    }

    // MARK: — Query Update

    /// Replace the query (e.g. when filter changes) and immediately re-fetch.
    func update(query: SQLSelectQuery) {
        self.query = query
        fetch()
    }

    // MARK: — Fetch

    func fetch() {
        isLoading = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fetched = self.query.decode(T.self)
            DispatchQueue.main.async {
                self.results = fetched
                self.isLoading = false
            }
        }
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
```

---

## 5. @SQLQuery Property Wrapper

**File:** `DB/Extensions/SQLQuery.swift`

Convenience property wrapper for use directly in SwiftUI Views, mirroring the SwiftData `@Query` pattern.

```swift
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
struct SQLQuery<T: SQLDecodable>: DynamicProperty {

    @State private var store: SQLQueryStore<T>

    init(query: SQLSelectQuery, type: T.Type, watch tables: [String]) {
        _store = State(initialValue: SQLQueryStore(query: query, type: type, watchTables: tables))
    }

    var wrappedValue: SQLQueryStore<T> {
        store
    }

    /// Convenience access: $exercises gives the store, exercises.results gives [T]
    var projectedValue: Binding<SQLQueryStore<T>> {
        $store
    }
}
```

---

## 6. Usage Examples

### Simple filtered list in a View

```swift
struct ExerciseListView: View {

    @SQLQuery(
        query: SQLSelectQuery("Exercise")
            .where("category", .equals, "Chest")
            .orderBy("name", .ascending),
        type: Exercise.self,
        watch: ["Exercise"]
    ) var exercises

    var body: some View {
        List(exercises.results, id: \.id) { exercise in
            ExerciseRow(exercise: exercise)
        }
        .overlay {
            if exercises.isLoading { ProgressView() }
        }
    }
}
```

### Multi-filter query (the hard case with raw SQLSwiftUIPackage)

```swift
// Before — raw string, error-prone:
let sql = "SELECT * FROM Exercise WHERE category = ? AND equipment IN (?,?) ORDER BY name ASC"

// After — type-safe, composable:
let query = SQLSelectQuery("Exercise")
    .where("category", .equals, selectedCategory)
    .where("equipment", .in, selectedEquipment)      // [String] auto-expands to IN (?,?,?)
    .where("difficulty", .equals, selectedDifficulty)
    .orderBy("name", .ascending)
    .limit(50)
```

### ViewModel with dynamic filters

```swift
@Observable
final class ExerciseViewModel {

    var selectedCategory: String = "All"
    var selectedMuscle: String = "All"
    var searchText: String = ""

    private(set) var exercises: [Exercise] = []
    private var store: SQLQueryStore<Exercise>

    init() {
        store = SQLQueryStore(
            query: Self.buildQuery(category: "All", muscle: "All", search: ""),
            type: Exercise.self,
            watchTables: ["Exercise"]
        )
        // Forward store results
        exercises = store.results
    }

    func applyFilters() {
        let query = Self.buildQuery(
            category: selectedCategory,
            muscle: selectedMuscle,
            search: searchText
        )
        store.update(query: query)
        exercises = store.results
    }

    private static func buildQuery(category: String, muscle: String, search: String) -> SQLSelectQuery {
        var q = SQLSelectQuery("Exercise").orderBy("name")
        if category != "All" { q = q.where("category", .equals, category) }
        if muscle != "All"   { q = q.where("primaryMuscle", .equals, muscle) }
        if !search.isEmpty   { q = q.where("name", .like, "%\(search)%") }
        return q
    }
}
```

### JOIN query (workout history with sets)

```swift
let query = SQLSelectQuery("WorkoutSession")
    .join("INNER JOIN CompletedSet ON CompletedSet.sessionId = WorkoutSession.id")
    .where("WorkoutSession.exerciseId", .equals, exerciseId)
    .orderBy("WorkoutSession.date", .descending)
    .limit(30)

let sessions = query.decode(WorkoutSession.self)
```

### Transaction with change notification

```swift
// After a multi-table transaction, notify all affected tables:
let sqlAndParams: [[String: Any]] = [
    WorkoutSession.insertSQL(session),
    CompletedSet.insertSQL(set1),
    CompletedSet.insertSQL(set2)
]
let status = DataManager.dataAccess.executeTransaction(sqlAndParams)
if status {
    SQLNotificationCenter.shared.post(tablesChanged: ["WorkoutSession", "CompletedSet"])
}
// → All SQLQueryStores watching either table re-fetch automatically
```

---

## 7. Fitamatic Table → Watch Mapping

| View | Query Table(s) | watchTables |
|---|---|---|
| Exercise Library | `Exercise` | `["Exercise"]` |
| Active Workout | `CompletedSet` | `["CompletedSet"]` |
| Workout History | `WorkoutSession` | `["WorkoutSession", "CompletedSet"]` |
| Exercise Detail / PRs | `CompletedSet` | `["CompletedSet"]` |
| Body Specs | `BodySpecs` | `["BodySpecs"]` |
| Home Dashboard | `WorkoutSession` | `["WorkoutSession"]` |

---

## 8. Implementation Order for Claude Agent

Complete these files in order. Each step is independently testable.

```
Step 1: SQLNotificationCenter.swift
        — No dependencies. Test: post + subscribe in a unit test.

Step 2: SQLSelectQuery.swift
        — No dependencies. Test: build() output matches expected SQL strings.

Step 3: SQLQueryDecoder.swift
        — Depends on SQLSelectQuery. Test: decode() on mock [[String:Any]].

Step 4: Exercise+SQL.swift (SQLDecodable conformance + write helpers with notifications)
        — Depends on steps 1–3. Test: insert then fetch in integration test.

Step 5: SQLQueryStore.swift
        — Depends on all above. Test: store updates after notification post.

Step 6: SQLQuery.swift
        — Depends on SQLQueryStore. Test: SwiftUI preview with @SQLQuery.

Step 7: Repeat SQLDecodable conformances for all remaining models:
        WorkoutSession, CompletedSet, BodySpecs, UserProfile, WorkoutTemplate
```

---

## 9. Key Rules

- **Never modify SQLSwiftUIPackage source.** All extensions live in the Fitamatic target.
- **Always call `SQLNotificationCenter.shared.post(tableChanged:)` after every successful write** — insert, update, upsert, delete. Missing a post means reactive stores won't update.
- **`SQLQueryStore.fetch()` runs on a background thread** — results are published back on `DispatchQueue.main`. Do not call `DataManager.dataAccess` on the main thread for large queries.
- **`SQLSelectQuery` is a value type (struct)** — all modifier methods return a new copy. Chain them freely; the original is never mutated.
- **`SQLDecodable.decode(row:)` must be nil-safe** — use `guard let` for required columns, optional chaining for nullable columns. Malformed rows are silently skipped via `compactMap`.
- **Table names must exactly match SQLite schema** — `SQLNotificationCenter` uses the table name string as the notification key. A typo means no updates. Use a `TableName` enum or constants file to prevent this.

---

## 10. TableName Constants (Recommended)

```swift
// DB/TableName.swift
enum TableName {
    static let exercise        = "Exercise"
    static let workoutSession  = "WorkoutSession"
    static let completedSet    = "CompletedSet"
    static let workoutTemplate = "WorkoutTemplate"
    static let bodySpecs       = "BodySpecs"
    static let userProfile     = "UserProfile"
}

// Usage:
SQLSelectQuery(TableName.exercise).where("category", .equals, "Chest")
SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
```