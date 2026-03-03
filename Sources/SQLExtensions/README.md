# SQLSwiftUIPackage Extensions

Reactive SELECT queries, type-safe query builder, and Swift Observation for SQLSwiftUIPackage.

## Overview

This extension package adds three missing capabilities to SQLSwiftUIPackage:

1. **Type-Safe SELECT Query Builder** — fluent `.where().orderBy().limit()` API
2. **Reactive SELECT Queries** — queries that automatically re-execute when data changes
3. **Swift Observation** — `@Observable` ViewModels and SwiftUI `@Query` property wrapper

## Components

### SQLNotificationCenter
Lightweight notification bus for SQLite table change events. Post after every write operation.

```swift
// After a successful insert/update/delete
SQLNotificationCenter.shared.post(tableChanged: "Exercise")

// After a transaction affecting multiple tables
SQLNotificationCenter.shared.post(tablesChanged: ["WorkoutSession", "CompletedSet"])
```

### SQLSelectQuery
Fluent, type-safe SELECT query builder.

```swift
let query = SQLSelectQuery("Exercise")
    .where("category", .equals, "Chest")
    .where("equipment", .in, ["Barbell", "Dumbbell"])
    .orderBy("name", .ascending)
    .limit(20)

let (sql, params) = query.build()
// Or execute directly:
let rows = query.execute()  // Returns [[String: Any]]
```

### SQLDecodable Protocol
Decode raw SQL results into typed models.

```swift
extension Exercise: SQLDecodable {
    static func decode(row: [String: Any]) -> Exercise? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String else { return nil }
        return Exercise(id: id, name: name, ...)
    }
}

// Now you can decode directly:
let exercises = query.decode(Exercise.self)  // Returns [Exercise]
```

### SQLQueryStore
`@Observable` reactive store that automatically re-fetches when watched tables change.

```swift
@Observable
final class ExerciseViewModel {
    private let store: SQLQueryStore<Exercise>
    
    var exercises: [Exercise] { store.results }
    var isLoading: Bool { store.isLoading }
    
    init() {
        store = SQLQueryStore(
            query: SQLSelectQuery("Exercise").orderBy("name"),
            type: Exercise.self,
            watchTables: ["Exercise"]
        )
    }
    
    func applyFilter(category: String) {
        let newQuery = SQLSelectQuery("Exercise")
            .where("category", .equals, category)
            .orderBy("name")
        store.update(query: newQuery)
    }
}
```

### @SQLQuery Property Wrapper
Use queries directly in SwiftUI views.

```swift
struct ExerciseListView: View {
    @SQLQuery(
        query: SQLSelectQuery("Exercise")
            .where("category", .equals, "Chest")
            .orderBy("name"),
        type: Exercise.self,
        watch: ["Exercise"]
    ) var exercises
    
    var body: some View {
        List(exercises.results, id: \.id) { exercise in
            Text(exercise.name)
        }
        .overlay {
            if exercises.isLoading {
                ProgressView()
            }
        }
    }
}
```

### TableName Constants
Prevent typos with string constants.

```swift
SQLSelectQuery(TableName.exercise)
SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
```

## Integration

1. Import the module:
```swift
import SQLExtensions
```

2. Add notification calls after writes:
```swift
@discardableResult
static func insertExercise(_ obj: Exercise) -> Bool {
    let sqlParams = obj.getSQLInsert()
    let status = DataManager.dataAccess.executeStatement(
        sqlParams["SQL"] as! String,
        withParams: sqlParams["PARAMS"] as! [Any]
    )
    if status {
        SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
    }
    return status
}
```

3. Implement `SQLDecodable` for your models:
```swift
extension MyModel: SQLDecodable {
    static func decode(row: [String: Any]) -> MyModel? {
        // Map SQL row to your model
    }
}
```

## Key Rules

- **Always call `SQLNotificationCenter.shared.post(tableChanged:)` after every successful write**
- **`SQLQueryStore.fetch()` runs synchronously on MainActor** — use it from the main thread
- **`SQLSelectQuery` is a value type** — all modifiers return a new copy
- **Use `TableName` constants** to prevent typos in table names

## Example: Complete Feature

```swift
// 1. Define model
struct Exercise: Codable, Sqldb {
    var tableName: String? = "Exercise"
    var id: Int?
    var name: String?
    var category: String?
}

// 2. Implement SQLDecodable
extension Exercise: SQLDecodable {
    static func decode(row: [String: Any]) -> Exercise? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String else { return nil }
        return Exercise(
            id: id,
            name: name,
            category: row["category"] as? String
        )
    }
}

// 3. Add write helpers with notifications
extension Exercise {
    @discardableResult
    static func insert(_ exercise: Exercise) -> Bool {
        let sqlParams = exercise.getSQLInsert()
        let status = DataManager.dataAccess.executeStatement(
            sqlParams["SQL"] as! String,
            withParams: sqlParams["PARAMS"] as! [Any]
        )
        if status {
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }
        return status
    }
}

// 4. Use in SwiftUI
struct ExerciseListView: View {
    @SQLQuery(
        query: SQLSelectQuery(TableName.exercise)
            .orderBy("name", .ascending),
        type: Exercise.self,
        watch: [TableName.exercise]
    ) var exercises
    
    var body: some View {
        List(exercises.results, id: \.id) { exercise in
            Text(exercise.name ?? "")
        }
        .toolbar {
            Button("Add") {
                let newExercise = Exercise(id: nil, name: "Bench Press", category: "Chest")
                Exercise.insert(newExercise)
                // List automatically updates!
            }
        }
    }
}
```

## License

The MIT License (MIT)
