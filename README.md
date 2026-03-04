# SQLSwiftUIPackage
SQLSwiftUIPackage is a Swift Package which includes SQLDataAccess, DataManager, Sqldb in Swift.

Supports Reactive Select Queries, that automatically re-execute and publish new results when underlying data changes in SwiftUI.

Type Safe Query Builder, supports insert/update/upsert but for select statements.

Swift Observations for @Observable View Models and SwiftUI's @Query equivalent property wrapper for easy SwiftUI View Model integration.

It makes using SQLite super easy and intuitive.

##SQLExtensions - Reactive Queries & SwiftUI Integration

SQLSwiftUIPackage now includes **SQLExtensions**, a powerful set of tools for modern SwiftUI development:

- 🔍 **Type-Safe Query Builder** - Fluent `.where().orderBy().limit()` API
- ⚡️ **Reactive Queries** - Auto-updating queries when data changes
- 👁️ **Swift Observation** - `@Observable` ViewModels
- 📱 **SwiftUI Property Wrapper** - `@SQLQuery` for seamless view integration
- ⚡️ **SwiftData-like App Group Support** - `@SQLContainer` for SwiftData-like Containers for Widget & Extension support to share a database seemlessly between apps.

See [SQLExtensions Examples](#sqlextensions-examples) below for detailed usage.

## Adding to Your Project
You only need to add SQLSwiftUIPackage to your Xcode Project to use.

It will also add two other packages, Apples Logger, and ObjectMapper, this is done automatically through the package dependencies.
  
To add this package go to Xcode Project 'Info' 'Build Settings' 'Swift Packages' select 'Swift Packages' and hit the '+' button and then enter the URL(git@github.com:pmurphyjam/SQLSwiftUIPackage.git) for this. Xcode should then do the rest for you. There will be three Packages, SQLDataAccess, DataManager, Sqldb, click on all three.

## Initializing SQLSwiftUIPackage

The SQLSwiftUIPackage is first of all easy to instantiate since it's a Swift Package.

The default SQL DB is named, "SQLite.db", but you can name it anything by calling setDBName. You do this all through DataManager. First init DataManager, then setDBName, then open the DB connection. This actually copies the DB into the Documents directory so it can be accessed.

```swift
    DataManager.init()
    DataManager.setDBName(name:"MySQL.db")
    let opened = DataManager.openDBConnection()
```
   You will need to put "MySQL.db" into a Resources directory so Xcode can see it. You can then edit the tables in "MySQL.db" or use Table Create to create your own tables for it. DataManager expects to find "MySQL.db" in Bundle directory of your App. If your DB is copied correctly opened will return true.
   
## Writing SQL Statements with Codable Models

SQLSwiftUIPackage with Sqldb.swift makes it super easy to create SQL Queries like: 

'insert into AppInfo (name,value,descrip) values(?,?,?)'

In addition queries like insert and update are created automatically for you so you don't have to write these out. To do this you need to create a Codable model for your DB table.

```swift
import UIKit
import ObjectMapper
import SQLDataAccess
import Sqldb
struct AppInfo: Codable,Sqldb,Mappable {
    
    //Define tableName for Sqldb required for Protocol
    var tableName : String? = "AppInfo"
    var name : String? = ""
    var value : String? = ""
    var descrip : String? = ""
    var date : Date? = Date()
    var blob : Data?
    //Optional sortAlpha default is false
    var sortAlpha: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case value = "value"
        case descrip = "descrip"
        case date = "date"
        case blob = "blob"
    }
    
    init?(map: Map) {
    }
    
    public mutating func mapping(map: Map) {
        name <- map["name"]
        value <- map["value"]
        descrip <- map["descrip"]
        date <- map["date"]
        blob <- map["blob"]
    }
    
    public func dbDecode(dataArray:Array<[String:AnyObject]>) -> [AppInfo]
    {
        //Maps DB dataArray [SQL,PARAMS] back to AppInfo from a DB select or read
        var array:[AppInfo] = []
        for dict in dataArray
        {
            let appInfo = AppInfo(JSON:dict )!
            array.append(appInfo)
        }
        return array
    }
        
    init (name:String,value:String,descrip:String,date:Date,blob:Data)
    {
        self.name = name
        self.value = value
        self.descrip = descrip
        self.date = date
        self.blob = blob
    }
    
    public init() {
        name = ""
        value = ""
        descrip = ""
        date = Date()
        blob = nil
    }
}

```

  The AppInfo.swift struct shows you how to write your Codable Models for your DB. It uses Codable, Sqldb, and Mappable. You need to define 'tableName' and then all the columns in your DB table. The func dbDecode Maps the SQL & PARAMS Dictionary which you get back from SQLDataAccess back to an AppInfo struct for you so your View Controller can consume it. You will need to follow the above construct for all your tables in SQLite.
  
### Create Your Models 
  
  You will also need to create a Models.swift struct which creates your SQL functions for AppInfo. InsertAppInfoSQL automatically creates the insert SQL & PARAMS Dictionary for you by using the Sqldb.getSQLInsert() method. The same goes for updateAppInfoSQL. Both these methods insert or update Null or Nil data. If you want the SQL to skip over Null or Nil data in the SQL & PARAMS use the sqldb.getSQLInsertValid() or sqldb.getSQLUpdateValid methods, and only valid data will be inserted or updated. The function Models.getAppInfo reads the DB and returns SQL & PARAMS Dictionary and then Maps this to the AppInfo struct by using dbDecode method, and does this in just 7 lines of code for any structure.
  
  The Sqldb package creates the SQL for update, insert, and upsert for you automatically so you don't need to write the SQL for these common queries. An updateValid, insertValid, and upsertValid checks the vars or parameters in your query, and if the values are unknown or nil then the update does not change the values in the existing table thus retaining prior values all ready written into the DB. 
  
  To use these Sqldb methods to generate your SQL queries automatically, just call them on your Codable model as : getSQLInsert(), getSQLInsertValid(), getSQLUpdate(whereItems:), getSQLUpdateValid(whereItems:), getSQLUpsertValid(whereItems:,forId:). Upsert is explained more later in this document.
 
 ```swift
import Foundation
import Logging
import DataManager

struct Models {

    static let SQL             = "SQL"
    static let PARAMS          = "PARAMS"
    
    static var log: Logger
    {
        var logger = Logger(label: "Models")
        logger.logLevel = .debug
        return logger
    }
    
    // MARK: - AppInfo
    static func insertAppInfoSQL(_ obj:AppInfo) -> Dictionary<String,Any>
    {
        //Let Sqldb create the SQL insert syntax for us
        //creates SQL : insert into AppInfo (name,value,descript,date,blob) values(?,?,?,?,?)
        let sqlParams = obj.getSQLInsert()!
        log.debug("insertAppInfoSQL : sqlParams = \(sqlParams) ")
        return sqlParams
    }
    
    @discardableResult static func insertAppInfo(_ obj:AppInfo) -> Bool
    {
        let sqlParams = self.insertAppInfoSQL(obj)
        let status = DataManager.dataAccess.executeStatement(sqlParams[SQL] as! String, withParams: sqlParams[PARAMS] as! Array<Any>)
        return status
    }
    
    static func insertAppInfoValidSQL(_ obj:AppInfo) -> Dictionary<String,Any>
    {
        //Let Sqldb create the SQL insert syntax for us
        //creates SQL : insert into AppInfo (name,value,descript,date,blob) values(?,?,?,?,?)
        let sqlParams = obj.getSQLInsertValid()!
        log.debug("insertAppInfoValidSQL : sqlParams = \(sqlParams) ")
        return sqlParams
    }
    
    @discardableResult static func insertAppInfoValid(_ obj:AppInfo) -> Bool
    {
        let sqlParams = self.insertAppInfoValidSQL(obj)
        let status = DataManager.dataAccess.executeStatement(sqlParams[SQL] as! String, withParams: sqlParams[PARAMS] as! Array<Any>)
        return status
    }
    
    static func updateAppInfoSQL(_ obj:AppInfo) -> Dictionary<String,Any>
    {
        //Let Sqldb create the SQL update syntax for us
        //creates SQL : update AppInfo set value = ?, descrip = ?, data = ?, blob = ? where name = ?
        let sqlParams = obj.getSQLUpdate(whereItems:"name")!
        log.debug("updateAppInfoSQL : sqlParams = \(sqlParams) ")
        return sqlParams
    }
    
    @discardableResult static func updateAppInfo(_ obj:AppInfo) -> Bool
    {
        let sqlParams = self.updateAppInfoSQL(obj)
        let status = DataManager.dataAccess.executeStatement(sqlParams[SQL] as! String, withParams: sqlParams[PARAMS] as! Array<Any>)
        return status
    }
    
    static func updateAppInfoValidSQL(_ obj:AppInfo) -> Dictionary<String,Any>
    {
        //Let Sqldb create the SQL update syntax for us
        //creates SQL : update AppInfo set value = ?, descrip = ?, data = ?, blob = ? where name = ?
        let sqlParams = obj.getSQLUpdateValid(whereItems:"name")!
        log.debug("updateAppInfoSQL : sqlParams = \(sqlParams) ")
        return sqlParams
    }
    
    @discardableResult static func updateAppInfoValid(_ obj:AppInfo) -> Bool
    {
        let sqlParams = self.updateAppInfoValidSQL(obj)
        let status = DataManager.dataAccess.executeStatement(sqlParams[SQL] as! String, withParams: sqlParams[PARAMS] as! Array<Any>)
        return status
    }
    
    static func upsertAppInfoValidSQL(_ obj:AppInfo) -> Dictionary<String,Any>
    {
        //Let Sqldb create the SQL upsert syntax for us
	//creates update or insert SQL : insert into AppInfo (name,value,descript,date,blob) values(?,?,?,?,?) on conflict(id) do update set 
	//value = ?, descrip = ?, data = ?, blob = ? where name = ?
        let sqlParams = obj.getSQLUpsertValid(whereItems:"name",forId:"id")!
        log.debug("upsertAppInfoValidSQL : sqlParams = \(sqlParams) ")
        return sqlParams
    }
    
    @discardableResult static func upsertAppInfoValid(_ obj:AppInfo) -> Bool
    {
        let sqlParams = self.upsertAppInfoValidSQL(obj)
        let status = DataManager.dataAccess.executeStatement(sqlParams[SQL] as! String, withParams: sqlParams[PARAMS] as! Array<Any>)
        return status
    }
    
    static func getAppInfo() -> [AppInfo]
    {
        let appInfo:AppInfo? = AppInfo()
        let dataArray = DataManager.dataAccess.getRecordsForQuery("select * from AppInfo ")
        let appInfoArray = appInfo?.dbDecode(dataArray:dataArray as! Array<[String : AnyObject]>)
        return appInfoArray!
    }
    
    static func doesAppInfoExistForName(_ name:String) -> Bool
    {
        var status:Bool? = false
        let dataArray = DataManager.dataAccess.getRecordsForQuery("select name from AppInfo where name = ?",name)
        if (dataArray.count > 0)
        {
            status = true
        }
        return status!
    }
 
 ```
  
  And that's it, now you can add additional methods to your Model's struct and create Models for other tables if you want. 
  
  Since this is just a Swift Package, it doesn't include AppInfo or Models, but 
  
  [SQLiteDemo](https://github.com/pmurphyjam/SQLiteDemo).
  
  Shows you how to use this Swift Package and creates these structures and models for you.
  
  For your App you'll need to create a new AppInfo struct and the equivalent Model for it.
  
## Advantages of using SQLSwiftUIPackage
  
  As you can see writing the SQL statements is easy for your Models since SQLDataAccess supports writing the SQL statements directly with simple strings like, 'select * from AppInfo'. You don't need to worry about Preferred Statements and obscure SQLite3 low level C method calls, SQLDataAccess does all that for you, and is battle tested so it doesn't leak memory and uses a queue to sync all your operations so they are guaranteed to complete on the proper thread. SQLDataAccess can run on the back ground thread or the foreground thread without crashing unlike Core Data and Realm. Typically you'll write or insert into your DB on a back ground thread through a Server API using Alamofire and decode the Server JSON using the Codable Model defined in AppInfo.swift. Once your data has been written into SQLite, then just issue a completion event to your View Controller, and then call your View Model which will then consume the data from SQLDataAccess on the foreground thread to display your just updated data in your view controller so it can display it.

You can also write the SQL Queries if you choose too, but having the Models.swift do it for you takes advantage of Sqldb extension which creates the inserts and updates for you automatically as long as you define your Codable model properly. 

## SQL Transactions

SQLDataAccess supports high performance SQL Transactions for insert or update along with select SQL statements. This is where you can literally write 1,000 inserts or updates into the DB all at once, and SQLite will do this very quickly. In addition you can perform select Transactions where you can literally query a 1,000 select statements at once and retrieve all the results of this query. All Transactions are is an Array of SQL Queries that are append together, and then you execute all of them at once with:

```swift
   let status1 = DataManager.dataAccess.executeTransaction(sqlAndParams)
   OR
   let dataArray = DataManager.dataAccess.getRecordsForQueryTrans(sqlAndParams)
```

The advantage of this is you can literally insert, update, or select 1,000 Objects at once which is exponentially faster than doing individual inserts, updates or selects back to back. This comes in very handy when your Server API returns a hundred JSON objects that need to be saved in your DB quickly, or you're querying a 100 selects and displaying these Objects in a View. SQLDataAccess spends no more than a few hundred milliseconds writing all that data into the DB, rather than seconds if you were to do them individually.

The executeStatementSQL and getRecordsForQuerySQL will take a regular SQL Query with Parameters and output sqlAndParams Array's that can be appended too and consumed by executeTransaction or getRecordsForQueryTrans.

The power of Transactions give's SQLite high performance capabilities.

## Back Ground Concurrent Processes
SQLDataAccess supports synchronous inserts or updates, and can also perform writes on background concurrent threads into SQLite, this can speed up writing into the DB for transactions or inserts or updates, just call any of the DataAccess methods with a '**BG**' after the method name in order to execute these methods. These background methods can dramatically speed up the writing of the data into SQLite for large amounts of data.

## Simple SQL Queries

When you write your SQL Queries as a String, all the terms that follow are in a variadic argument list of type Any, and your parameters are in an Array. All these terms are separated by commas in your list of SQL arguments. You can enter Strings, Integers, Date’s, and Blobs right after the sequel statement since all of these terms are considered to be parameters for the SQL. The variadic argument array just makes it convenient to enter all your sequel in just one executeStatement or getRecordsForQuery call. If you don’t have any parameters, don’t enter anything after your SQL.

## Upsert Capability For High Performance

Usually in order for you to insert or update the SQLite DB, you need to know if the data already exists in the DB or not. As such you usually execute a SQL query to determine if the data exists, if it does you do an update, if it doesn't you then do an insert. When fetching lots of data from a Server where megabytes of JSON comes down and then needs to be written into the DB, the SQL query to determine if it exists or not can become expensive performance wise. To get around this issue SQLite supports Upsert which is really just an Insert followed by an On Conflict(id) Do Update SQL Query. The On Conflict statement needs an indexed column that is unique in order to work, a column like id will work. Using the Upsert command you now don't need a separate lookup anymore, and your Codable Model can just parse the JSON and then write it directly into the DB using the Upsert command. The Upsert SQL query will determine if it needs to do an insert or an update automatically. The Sqldb package will create the SQL for you for the Upsert command, simply call Sqldb : getSQLUpsertValid(whereItems:"items",forId:"id") where the forId is the column that is indexed and has to be unique.

Using Upsert you can see a 2X performance speed up for inserting or updating large amounts of data into SQLite.

## Data Types SQLDataAccess Supports

The results array is an Array of Dictionary’s where the ‘key’ is your tables column name, and the ‘value’ is your data obtained from SQLite. You can easily iterate through this array with a for loop or print it out directly or assign these Dictionary elements to custom data object Classes that you use in your View Controllers for model consumption.

SQLDataAccess will store, ***text, double, float, blob, Date, integer and long long integers***. 

For Blobs you can store ***binary, varbinary, blob, Data.***

You can store Swift Data types directly.

For Text you can store ***char, character, clob, national varying character, native character, nchar, nvarchar, varchar, variant, varying character, text***.

For Dates you can store ***datetime, time, timestamp, date.*** No need to convert Dates to Strings and back and forth, SQLDataAccess does all that for you! Dates should always be stored as UTC in the DB and are stored using DataFormatter ***yyyy-MM-dd HH:mm:ss*** so DataFormatter takes care of day light savings time for the "en\_US\_POSIX" local you are in.

For Integers you can store ***bigint, bit, bool, boolean, int2, int8, integer, mediumint, smallint, tinyint, int.***

For Doubles you can store ***decimal, double precision, float, numeric, real, double.*** Double has the most precision.

You can even store Nulls of type ***Null.***

You can also store Swift UUID directy of type ***UUID.***

You just declare these types in tables, and and your Codable struct, and SQLDataAccess does the rest for you!

## Support for Foreign Keys
SQLite supports foreign Keys which are used to enforce relationships between table Id's. These keys speed up your SQL queries and make it easy to delete or update items in tables quickly. By default SQLite comes with foreignKeys disabled, you have to turn it on with:

```swift
DataManager.openDBConnection()
DataManager.dataAcess.foreignKeys(true)

```
Now foreign Key access is enabled and checked on all your SQL queries. Typically the Id's are primary keys that exist in the Parent and Child tables with the Child table having the foreign key constraints. The Id's must unique and can not be Null, and you can delay the foreign key check by adding a deferred clause, this means they will only be checked when the transaction is committed. For more information on foreign keys search for 'SQLite Foreign Key Support' in Google.

## SQLCipher and Encryption
	
In addition SQLDataAccess will also work with SQLCipher, and it's pretty easy to do. To use SQLCipher you must remove 'libsqlite3.tbd' and add 'libsqlcipher-ios.a'. You must also add '-DSQLITE_HAS_CODEC', you then encrypt the Database by calling DataManager.dbEncrypt(key), and you can decrypt it using DataManager.dbDecrypt(). You just set your encryption key, and your done. 

## Battle Tested and High Performance

SQLDataAccess is a very fast and efficient class and guaranteed to not leak memory, and uses the low level C calls from SQLite, and nothing is faster then low level C. In addition it is thread safe so you can read or write your DB on the foreground or background threads without crashing or corrupting your data. SQLDataAccess can be used in place of CoreData or Realm or FMDB. CoreData really just uses SQLite as it's underlying data store without all the CoreData integrity fault crashes that come with CoreData. CoreData and Realm need to update their models on the main thread which is a real problem if you're trying to display data in a view controller which is consuming a lot of data at the same time. This means your view controller will become slow and not scroll efficiently for a TableView or CollectionView because it's updating CoreData or Realm Entities. In addition if you do these updates on a background thread Core Data and Realm will crash. SQLDataAccess has none of these threading problems, and you can read or write data on either the background or foreground threads.

So make your life easier, and all your Apps more reliable, and use SQLSwiftUIPackage, and best of all it's free with no license required!

---

## SQLExtensions Examples

The SQLExtensions module provides a modern, reactive approach to working with SQLite in SwiftUI applications. Here are comprehensive examples showing all four key features.

### 1. Type-Safe Query Builder

Build complex SELECT queries with a fluent, type-safe API instead of error-prone SQL strings.

```swift
import SQLExtensions

// Simple query
let basicQuery = SQLSelectQuery("Exercise")
    .where("category", .equals, "Chest")
    .orderBy("name", .ascending)
    .limit(20)

let (sql, params) = basicQuery.build()
// SQL: "SELECT * FROM Exercise WHERE category = ? ORDER BY name ASC LIMIT 20"
// params: ["Chest"]

// Complex query with multiple conditions
let advancedQuery = SQLSelectQuery("Exercise")
    .where("category", .equals, "Chest")
    .where("equipment", .in, ["Barbell", "Dumbbell", "Cable"])
    .where("difficulty", .notEquals, "Beginner")
    .whereNotNull("videoUrl")
    .orderBy("name", .ascending)
    .limit(50)
    .offset(10)

// Query with JOIN
let joinQuery = SQLSelectQuery("WorkoutSession")
    .join("INNER JOIN Exercise ON Exercise.id = WorkoutSession.exerciseId")
    .where("WorkoutSession.userId", .equals, currentUserId)
    .orderBy("WorkoutSession.date", .descending)
    .limit(30)

// Execute directly
let rows = basicQuery.execute()  // Returns [[String: Any]]
```

**Supported Operators:**
- `.equals`, `.notEquals`
- `.lessThan`, `.greaterThan`, `.lessThanOrEq`, `.greaterThanOrEq`
- `.like`, `.notLike`
- `.in` (for arrays)
- `.isNull`, `.isNotNull` (via `whereNull()` and `whereNotNull()`)

### 2. Reactive Queries with SQLNotificationCenter

Automatically re-execute queries when underlying data changes.

```swift
import SQLExtensions

// Step 1: Implement SQLDecodable for your model
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

// Step 2: Use SQLQueryStore for reactive queries
@Observable
final class ExerciseListViewModel {
    private let store: SQLQueryStore<Exercise>

    var exercises: [Exercise] { store.results }
    var isLoading: Bool { store.isLoading }
    var error: String? { store.error }

    init() {
        // Create a reactive store that watches the Exercise table
        store = SQLQueryStore(
            query: SQLSelectQuery(TableName.exercise)
                .orderBy("name", .ascending),
            type: Exercise.self,
            watchTables: [TableName.exercise]
        )
    }

    func filterByCategory(_ category: String) {
        let newQuery = SQLSelectQuery(TableName.exercise)
            .where("category", .equals, category)
            .orderBy("name", .ascending)

        store.update(query: newQuery)
    }
}

// Step 3: Add notifications after write operations
extension Exercise {
    @discardableResult
    static func insert(_ exercise: Exercise) -> Bool {
        let sqlParams = exercise.getSQLInsert()
        let status = DataManager.dataAccess.executeStatement(
            sqlParams["SQL"] as! String,
            withParams: sqlParams["PARAMS"] as! [Any]
        )

        if status {
            // This triggers ALL SQLQueryStores watching "Exercise" to refresh!
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }

        return status
    }

    @discardableResult
    static func update(_ exercise: Exercise) -> Bool {
        let sqlParams = exercise.getSQLUpdate(whereItems: "id")
        let status = DataManager.dataAccess.executeStatement(
            sqlParams["SQL"] as! String,
            withParams: sqlParams["PARAMS"] as! [Any]
        )

        if status {
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }

        return status
    }

    @discardableResult
    static func delete(id: Int) -> Bool {
        let status = DataManager.dataAccess.executeStatement(
            "DELETE FROM Exercise WHERE id = ?",
            id
        )

        if status {
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }

        return status
    }
}

// Multi-table transactions
func saveWorkout(session: WorkoutSession, sets: [CompletedSet]) {
    let sqlAndParams: [[String: Any]] = [
        session.getSQLInsert(),
        sets[0].getSQLInsert(),
        sets[1].getSQLInsert(),
        sets[2].getSQLInsert()
    ]

    let status = DataManager.dataAccess.executeTransaction(sqlAndParams)

    if status {
        // Notify multiple tables at once
        SQLNotificationCenter.shared.post(tablesChanged: [
            TableName.workoutSession,
            TableName.completedSet
        ])
        // All stores watching either table will auto-refresh!
    }
}
```

### 3. Swift Observation with @Observable ViewModels

Create fully observable ViewModels that integrate seamlessly with SwiftUI.

```swift
import SQLExtensions
import Observation

@Observable
@MainActor
final class WorkoutHistoryViewModel {
    private let sessionStore: SQLQueryStore<WorkoutSession>
    private let setStore: SQLQueryStore<CompletedSet>

    var sessions: [WorkoutSession] { sessionStore.results }
    var sets: [CompletedSet] { setStore.results }
    var isLoadingSessions: Bool { sessionStore.isLoading }
    var isLoadingSets: Bool { setStore.isLoading }

    // Filtered state
    var selectedExerciseId: Int? = nil {
        didSet {
            updateFilters()
        }
    }

    var dateRange: ClosedRange<Date>? = nil {
        didSet {
            updateFilters()
        }
    }

    init() {
        // Create multiple reactive stores
        sessionStore = SQLQueryStore(
            query: SQLSelectQuery(TableName.workoutSession)
                .orderBy("date", .descending)
                .limit(100),
            type: WorkoutSession.self,
            watchTables: [TableName.workoutSession]
        )

        setStore = SQLQueryStore(
            query: SQLSelectQuery(TableName.completedSet)
                .orderBy("timestamp", .descending),
            type: CompletedSet.self,
            watchTables: [TableName.completedSet]
        )
    }

    private func updateFilters() {
        // Build dynamic query based on filter state
        var query = SQLSelectQuery(TableName.workoutSession)

        if let exerciseId = selectedExerciseId {
            query = query.where("exerciseId", .equals, exerciseId)
        }

        if let range = dateRange {
            let formatter = ISO8601DateFormatter()
            query = query
                .where("date", .greaterThanOrEq, formatter.string(from: range.lowerBound))
                .where("date", .lessThanOrEq, formatter.string(from: range.upperBound))
        }

        query = query.orderBy("date", .descending).limit(100)

        sessionStore.update(query: query)
    }

    func refreshData() {
        sessionStore.fetch()
        setStore.fetch()
    }

    func getSetsForSession(_ sessionId: Int) -> [CompletedSet] {
        sets.filter { $0.sessionId == sessionId }
    }
}

// Use in SwiftUI
struct WorkoutHistoryView: View {
    @State private var viewModel = WorkoutHistoryViewModel()

    var body: some View {
        List {
            ForEach(viewModel.sessions, id: \.id) { session in
                WorkoutSessionRow(
                    session: session,
                    sets: viewModel.getSetsForSession(session.id)
                )
            }
        }
        .overlay {
            if viewModel.isLoadingSessions {
                ProgressView()
            }
        }
        .toolbar {
            Button("Refresh") {
                viewModel.refreshData()
            }
        }
    }
}
```

### 4. SwiftUI Property Wrapper (@SQLQuery)

Use queries directly in SwiftUI views with automatic updates.

```swift
import SQLExtensions
import SwiftUI

// Simple list with auto-updates
struct ExerciseListView: View {
    @SQLQuery(
        query: SQLSelectQuery(TableName.exercise)
            .orderBy("name", .ascending),
        type: Exercise.self,
        watch: [TableName.exercise]
    ) var exercises

    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            List(exercises.results, id: \.id) { exercise in
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    ExerciseRow(exercise: exercise)
                }
            }
            .overlay {
                if exercises.isLoading {
                    ProgressView("Loading exercises...")
                }
            }
            .navigationTitle("Exercises")
            .toolbar {
                Button("Add Exercise") {
                    showingAddSheet = true
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExerciseView()
            }
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading) {
            Text(exercise.name ?? "Unknown")
                .font(.headline)
            HStack {
                Text(exercise.category ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(exercise.equipment ?? "")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(4)
            }
        }
    }
}

// View with dynamic filtering
struct FilteredExerciseView: View {
    @State private var selectedCategory: String = "All"
    @State private var selectedMuscle: String = "All"
    @State private var searchText: String = ""

    @SQLQuery(
        query: SQLSelectQuery(TableName.exercise)
            .orderBy("name", .ascending),
        type: Exercise.self,
        watch: [TableName.exercise]
    ) var exercises

    var filteredResults: [Exercise] {
        exercises.results.filter { exercise in
            let categoryMatch = selectedCategory == "All" || exercise.category == selectedCategory
            let muscleMatch = selectedMuscle == "All" || exercise.primaryMuscle == selectedMuscle
            let searchMatch = searchText.isEmpty ||
                (exercise.name?.localizedCaseInsensitiveContains(searchText) ?? false)

            return categoryMatch && muscleMatch && searchMatch
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Filter controls
                HStack {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All").tag("All")
                        Text("Chest").tag("Chest")
                        Text("Back").tag("Back")
                        Text("Legs").tag("Legs")
                    }
                    .pickerStyle(.menu)

                    Picker("Muscle", selection: $selectedMuscle) {
                        Text("All").tag("All")
                        Text("Pectorals").tag("Pectorals")
                        Text("Lats").tag("Lats")
                        Text("Quads").tag("Quads")
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)

                // Results list
                List(filteredResults, id: \.id) { exercise in
                    ExerciseRow(exercise: exercise)
                }
                .searchable(text: $searchText, prompt: "Search exercises")
            }
            .navigationTitle("Exercises")
        }
    }
}

// View that modifies data (auto-updates other views!)
struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "Chest"
    @State private var equipment = "Barbell"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    Text("Chest").tag("Chest")
                    Text("Back").tag("Back")
                    Text("Legs").tag("Legs")
                }
                Picker("Equipment", selection: $equipment) {
                    Text("Barbell").tag("Barbell")
                    Text("Dumbbell").tag("Dumbbell")
                    Text("Machine").tag("Machine")
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let exercise = Exercise(
                            id: nil,
                            name: name,
                            category: category,
                            equipment: equipment
                        )

                        Exercise.insert(exercise)

                        // All @SQLQuery views watching "Exercise"
                        // will automatically update!
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
```

### Complete Example: Exercise Management

Here's a complete example showing all features together:

```swift
import SwiftUI
import SQLExtensions

// MARK: - Model
struct Exercise: Codable, Sqldb {
    var tableName: String? = "Exercise"
    var id: Int?
    var name: String?
    var category: String?
    var primaryMuscle: String?
    var equipment: String?
    var difficulty: String?
    var instructions: String?
}

// MARK: - SQLDecodable Implementation
extension Exercise: SQLDecodable {
    static func decode(row: [String: Any]) -> Exercise? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String else { return nil }

        return Exercise(
            id: id,
            name: name,
            category: row["category"] as? String,
            primaryMuscle: row["primaryMuscle"] as? String,
            equipment: row["equipment"] as? String,
            difficulty: row["difficulty"] as? String,
            instructions: row["instructions"] as? String
        )
    }
}

// MARK: - Write Helpers with Notifications
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

    @discardableResult
    static func update(_ exercise: Exercise) -> Bool {
        let sqlParams = exercise.getSQLUpdate(whereItems: "id")
        let status = DataManager.dataAccess.executeStatement(
            sqlParams["SQL"] as! String,
            withParams: sqlParams["PARAMS"] as! [Any]
        )
        if status {
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }
        return status
    }

    @discardableResult
    static func delete(id: Int) -> Bool {
        let status = DataManager.dataAccess.executeStatement(
            "DELETE FROM Exercise WHERE id = ?", id
        )
        if status {
            SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
        }
        return status
    }
}

// MARK: - SwiftUI Views
struct ExerciseManagementView: View {
    @SQLQuery(
        query: SQLSelectQuery(TableName.exercise)
            .orderBy("name", .ascending),
        type: Exercise.self,
        watch: [TableName.exercise]
    ) var exercises

    @State private var showingAddSheet = false
    @State private var selectedCategory: String = "All"

    var filteredExercises: [Exercise] {
        if selectedCategory == "All" {
            return exercises.results
        }
        return exercises.results.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag("All")
                    Text("Chest").tag("Chest")
                    Text("Back").tag("Back")
                    Text("Legs").tag("Legs")
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    ForEach(filteredExercises, id: \.id) { exercise in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name ?? "Unknown")
                                    .font(.headline)
                                Text(exercise.category ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                if let id = exercise.id {
                                    Exercise.delete(id: id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercises (\(filteredExercises.count))")
            .toolbar {
                Button("Add") {
                    showingAddSheet = true
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExerciseSheet()
            }
            .overlay {
                if exercises.isLoading {
                    ProgressView()
                }
            }
        }
    }
}

struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "Chest"
    @State private var equipment = "Barbell"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise Name", text: $name)
                Picker("Category", selection: $category) {
                    Text("Chest").tag("Chest")
                    Text("Back").tag("Back")
                    Text("Legs").tag("Legs")
                }
                Picker("Equipment", selection: $equipment) {
                    Text("Barbell").tag("Barbell")
                    Text("Dumbbell").tag("Dumbbell")
                    Text("Machine").tag("Machine")
                    Text("Bodyweight").tag("Bodyweight")
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let exercise = Exercise(
                            name: name,
                            category: category,
                            equipment: equipment
                        )
                        Exercise.insert(exercise)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ExerciseManagementView()
}
```

### Key Benefits

1. **Type Safety** - Catch errors at compile time instead of runtime
2. **Reactive Updates** - Views automatically refresh when data changes
3. **Less Boilerplate** - No manual observation or notification handling
4. **SwiftUI Native** - Works seamlessly with `@Observable` and SwiftUI lifecycle
5. **Testable** - Easy to mock and test queries independently
6. **Performance** - Queries run on background threads, updates on main thread
7. **Maintainable** - Clear, readable query syntax

### Table Name Constants

Use `TableName` to prevent typos:

```swift
// Instead of string literals prone to typos:
SQLSelectQuery("Exercize")  // Typo! Won't match table

// Use constants:
SQLSelectQuery(TableName.exercise)  // Compile-time safety

// Available constants:
TableName.exercise
TableName.workoutSession
TableName.completedSet
TableName.workoutTemplate
TableName.bodySpecs
TableName.userProfile
```

For complete documentation, see `Sources/SQLExtensions/README.md`.

---

## SQLContainer - Simplified Setup with App Groups

`SQLContainer` provides a SwiftData-like API for easy database setup, including seamless App Group support for sharing data between your app, widgets, and extensions.

### Basic Setup

```swift
import SQLExtensions

@main
struct MyApp: App {
    let container: SQLContainer

    init() {
        // Simple setup - uses Documents directory
        do {
            container = try SQLContainer()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .sqlContainer(container) // Optional: inject into environment
    }
}
```

### App Group Setup (Share with Widgets & Extensions)

```swift
import SQLExtensions

@main
struct MyApp: App {
    let container: SQLContainer

    init() {
        do {
            // Setup with app group - automatically handles shared container
            container = try SQLContainer(
                configuration: SQLConfiguration(
                    databaseName: "MyApp.db",
                    groupIdentifier: "group.com.company.myapp"
                )
            )
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Widget with App Group

```swift
import WidgetKit
import SwiftUI
import SQLExtensions

struct ExerciseWidget: Widget {
    let kind: String = "ExerciseWidget"

    init() {
        // Same configuration as main app!
        try? SQLContainer.setupShared(
            databaseName: "MyApp.db",
            groupIdentifier: "group.com.company.myapp"
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ExerciseWidgetView(entry: entry)
        }
    }
}

struct Provider: TimelineProvider {
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Query data directly - container already setup!
        let exercises = SQLSelectQuery(TableName.exercise)
            .limit(5)
            .decode(Exercise.self)

        let entry = SimpleEntry(date: Date(), exercises: exercises)
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}
```

### Advanced Configuration Options

```swift
// Custom database name
let container = try SQLContainer(databaseName: "CustomDB.db")

// App group with custom settings
let container = try SQLContainer(
    configuration: SQLConfiguration(
        databaseName: "Workout.db",
        groupIdentifier: "group.com.fitness.app",
        copyFromBundle: true  // Copy from bundle if missing
    )
)

// Using shared instance pattern
try SQLContainer.setupShared(
    databaseName: "Shared.db",
    groupIdentifier: "group.com.company.app"
)

// Access anywhere in your app
let container = await SQLContainer.shared
```

### Comparison: Before vs After

**Before (Manual Setup):**
```swift
guard let groupURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.company.app"
) else { fatalError() }

let dbPath = groupURL.appendingPathComponent("MyApp.db").path

DataManager.init()
DataManager.setDBName(name: "MyApp.db")

if !FileManager.default.fileExists(atPath: dbPath) {
    if let bundlePath = Bundle.main.path(forResource: "MyApp", ofType: "db") {
        try? FileManager.default.copyItem(atPath: bundlePath, toPath: dbPath)
    }
}

let opened = DataManager.openDBConnection()
```

**After (SQLContainer):**
```swift
let container = try SQLContainer(
    databaseName: "MyApp.db",
    groupIdentifier: "group.com.company.app"
)
```

### Using with Environment (Optional)

```swift
struct ContentView: View {
    @Environment(\.sqlContainer) var container

    var body: some View {
        Text("Database: \(container?.databasePath ?? "None")")
    }
}
```

### Key Features

- ✅ **SwiftData-like API** - Familiar configuration pattern
- ✅ **Automatic App Group handling** - Handles all path resolution
- ✅ **Bundle copying** - Automatically copies database from bundle
- ✅ **Shared instance support** - Optional singleton pattern
- ✅ **SwiftUI environment** - Inject container into view hierarchy
- ✅ **Error handling** - Clear, descriptive errors
- ✅ **Type-safe** - Full Swift concurrency support

The `SQLContainer` makes it effortless to share your SQLite database across your app, widgets, and extensions!

