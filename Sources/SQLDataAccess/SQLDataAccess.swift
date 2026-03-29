//
//  SQLDataAccess.swift
//  SQLPackage
//
//  Created by Pat Murphy on 10/14/17.
//  The MIT License (MIT)
//

import Foundation
import Willow
import SQLite3

//Constants
let SQL             = "SQL"
let PARAMS          = "PARAMS"

public class SQLDataAccess: NSObject {
    
    nonisolated(unsafe) static let shared = SQLDataAccess()
    var DB_FILE = "SQLite.db"
    var DB2_FILE = "SQLite2.db"
    let SQLITE_DB_CORRUPTED = Notification.Name("SQLITE_DB_CORRUPTED")
    let SQLITE_DB_ERR_MESSAGE = Notification.Name("SQLITE_DB_ERR_MESSAGE")
    private var path:String!
    private let DB_Queue = "SQLiteQueue"
    private var queue:DispatchQueue!
    private let bgQueue = DispatchQueue(label: "com.SQLiteQueue.BG", qos: .background, attributes: .concurrent)
    private var sqlite3dbConn:OpaquePointer? = nil
    private let db_format = DateFormatter()
    private let SQLITE_DATE = SQLITE_NULL + 1
    private let SQLITE_UUID = SQLITE_NULL + 2
    private let SQLITE_STATIC = unsafeBitCast(0, to:sqlite3_destructor_type.self)
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to:sqlite3_destructor_type.self)
    private let EN_KEY = "45763887E33478287EFFEB42890CD1EF"
    public var rollBack:Bool = false
    public var enableLogs:Bool = false

    class Modifier: LogModifier {
        func modifyMessage(_ message: String, with logLevel: LogLevel) -> String {
            return "DA : \(message)"
        }
    }
    
    var log: Logger
    {
        var logger = Logger(logLevels: [.all], writers: [ConsoleWriter(modifiers:[Modifier()])], executionMethod: .synchronous(lock: NSRecursiveLock()))
        #if DEBUG
        logger.enabled = true
        #else
        logger.enabled = false
        #endif
        return logger
    }
    
    public override init() {
        super.init()
        queue = DispatchQueue(label:DB_Queue, attributes:[])
        //for 24-hour format need locale to work, ISO-8601 format
        db_format.locale = Locale(identifier:"en_US_POSIX")
        db_format.timeZone = TimeZone(secondsFromGMT:0)
        db_format.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }
    
    deinit {
        closeConnection()
    }
    
    @objc public func getDBName() -> String
    {
        return DB_FILE
    }
    
    public func setDBName(name:String)
    {
        DB_FILE = name
    }
    
    @objc public func getDB2Name() -> String
    {
        return DB2_FILE
    }
    
    public func setDB2Name(name:String)
    {
        DB2_FILE = name
    }
    
    @objc public func getDB2Path() -> String
    {
        return self.pathForFileWithName(fileName: self.DB2_FILE)
    }
    
    @objc public func getDBPath() -> String
    {
        return self.pathForFileWithName(fileName: self.DB_FILE)
    }
    
    public func createDB2()
    {
        let status = self.moveDBtoDocumentDirectoryForName(DB_FILE,dbName:DB2_FILE)
        log.debugMessage("createDB2 : status = \(status)")
    }
    
    public func closeConnection()
    {
        var rc = sqlite3_close(sqlite3dbConn)
        if(rc == SQLITE_BUSY)
        {
            let ps:OpaquePointer? = nil
            var stmt = sqlite3_next_stmt(sqlite3dbConn, ps)
            while (stmt != nil)
            {
                stmt = sqlite3_next_stmt(sqlite3dbConn, ps)
                sqlite3_finalize(stmt)
            }
            rc = sqlite3_close(sqlite3dbConn)
            if(rc == SQLITE_OK)
            {
                log.debugMessage("DB : CLOSED")
            }
            else if(rc == SQLITE_BUSY)
            {
                log.debugMessage("DB : BUSY CLOSED")
                sqlite3_finalize(stmt);
            }
        }
        sqlite3dbConn = nil;
    }
    
    public override var description:String {
        return "DA : DB path \(path!)"
    }
    
    public func dbDateStr(date:Date) -> String {
        return db_format.string(from:date)
    }
    
    public func dbStrDate(date:String) -> Date {
        return db_format.date(from:date)!
    }

    private func unwrappedParameterValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }

        guard let child = mirror.children.first else {
            return nil
        }

        return unwrappedParameterValue(child.value)
    }

    public func openConnection(copyFile:Bool = true) -> Bool {
        
        if(sqlite3dbConn != nil)
        {
            log.debugMessage("DB : OPENED")
            return true
        }
        else
        {
            log.debugMessage("DB : OPENING")
        }
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let path = (docDir as NSString).appendingPathComponent(DB_FILE)
        // Check if DB is there in Documents directory
        if !(fm.fileExists(atPath:path)) && copyFile {
            // The database does not exist, so copy it
            guard let rp = Bundle.main.resourcePath else { return false }
            let from = (rp as NSString).appendingPathComponent(DB_FILE)
            do {
                try fm.copyItem(atPath:from, toPath:path)

            } catch let error {
                assert(false, "DA : Failed to copy writable version of \(DB_FILE)! Error - \(error.localizedDescription)")
                return false
            }
        }
        // Open the DB
        let cpath = path.cString(using:String.Encoding.utf8)
        //let error = sqlite3_open(cpath!, &sqlite3dbConn)
        //We use Full Mutex so we can process on background concurrent dispatch queues for execution speed
        //All methods with a BG after their method call use this bgQueue
        let error = sqlite3_open_v2(cpath!, &sqlite3dbConn, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        if error != SQLITE_OK {
            // Open failed, close DB and fail
            log.errorMessage(" - failed to open \(self.DB_FILE)!")
            sqlite3_close(sqlite3dbConn)
            return false
        }
        else
        {
            log.debugMessage("\(self.DB_FILE) opened : path = \(path)")
        }
        
        return true
    }
    
    public func foreignKeys(_ enable:Bool)
    {   var sql = String()
        if(enable)
        {
            sql = String(format:"PRAGMA foreign_keys = ON;")
        }
        else
        {
            sql = String(format:"PRAGMA foreign_keys = OFF;")
        }
        sqlite3_exec(sqlite3dbConn, sql, nil, nil, nil);
        let errCode = Int(sqlite3_errcode(sqlite3dbConn))
        if(errCode != SQLITE_OK)
        {
            let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
            log.errorMessage(" : foreignKeys : sqlErrCode = \(errCode) : sqlErrMsg = \(errMsg!)")
            let options = ["Message":"foreignKeys Error : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))"]
            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
        }
    }
    
    public func setRollback(_ enable:Bool)
    {
        rollBack = enable
    }
    
    public func getRollback() -> Bool
    {
        return rollBack
    }
    
    public func getVersion() -> Int64
    {
        let sqliteVersion = sqlite3_libversion_number()
        return Int64(sqliteVersion)
    }
    
    public func setEnableLogs(_ enable:Bool)
    {
        enableLogs = enable
    }
    
    public func dbEncrypt(_ key:String)
    {
        let sql1 = String(format:"ft67s%@58uy%@fge4",EN_KEY,key)
        #if ENCRYPT
            //This method only exists in SQLCipher
            sqlite3_key(sqlite3dbConn,sql1,Int(strlen(sql1)))
        #endif
        let sql2 = String(format:"PRAGMA cipher = 'aes-256-cfb';")
        sqlite3_exec(sqlite3dbConn, sql2, nil, nil, nil);
        let errCode = Int(sqlite3_errcode(sqlite3dbConn))
        if(errCode != SQLITE_OK)
        {
            let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
            log.errorMessage(" : ENCRYPT : sqlErrCode = \(errCode) : sqlErrMsg = \(errMsg!)")
            let options = ["Message":"ENCRYPT Error : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))"]
            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
        }
    }
    
    public func dbDecrypt()
    {
        copyDBtoDocumentDirectory(copyDBFile: DB_FILE, toDBFile: DB_FILE+"X")
        let dbFileX = pathForFileWithName(fileName: DB_FILE+"X")
        let sql1 = String(format:"attach database '%@' as plaintext KEY '';",dbFileX)
        sqlite3_exec(sqlite3dbConn, sql1, nil, nil, nil)
        
        let sql2 = String(format:"select sqlcipher_export('plaintext');")
        sqlite3_exec(sqlite3dbConn, sql2, nil, nil, nil)
        
        let sql3 = String(format:"detach database plaintext;")
        sqlite3_exec(sqlite3dbConn, sql3, nil, nil, nil)
        let errCode = Int(sqlite3_errcode(sqlite3dbConn))
        if(errCode != SQLITE_OK)
        {
            let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
            log.errorMessage(" : DECRYPT : sqlErrCode = \(errCode) : sqlErrMsg = \(errMsg!)")
            let options = ["Message":"DECRYPT Error : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))"]
            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
        }
        replaceDBinDocumentDirectory(removeDBFile: DB_FILE, renameDBFile: DB_FILE+"X")
        let path = pathForFileWithName(fileName: DB_FILE)
        // Open the DB
        let cpath = path.cString(using:String.Encoding.utf8)
        let error = sqlite3_open(cpath!, &sqlite3dbConn)
        if error != SQLITE_OK {
            // Open failed, close DB and fail
            log.errorMessage(" - failed to open \(self.DB_FILE)!")
            sqlite3_close(sqlite3dbConn)
        }
        else
        {
            log.debugMessage(" : \(self.DB_FILE) opened : path = \(path)")
        }
        
    }
    
    private func stmt(_ ps: inout OpaquePointer!, forQuery query: String, withParams parameters: Array<Any>!) -> OpaquePointer! {
        
        if(sqlite3dbConn == nil)
        {
            return nil
        }
        //Use inout ps pointer so return can hit sqlite3_finalize
        var code:Int32 = -1
        
        //Do sanity check on query first to make sure it's Ok
        if let cSql = query.cString(using: String.Encoding.utf8) {
            code = sqlite3_prepare_v3(sqlite3dbConn, cSql, CInt(query.lengthOfBytes(using: String.Encoding.utf8)),UInt32(SQLITE_PREPARE_NORMALIZE), &ps, nil)
        }
        
        if(code == SQLITE_OK)
        {
            var flag:CInt = 0
            for i in 0 ..< parameters.count {
                let parameter = self.unwrappedParameterValue(parameters![i])

                if let val = parameter as? Double {
                    flag = sqlite3_bind_double(ps, CInt(i+1), CDouble(val))
                }
                else if let val = parameter as? Float {
                    flag = sqlite3_bind_double(ps, CInt(i+1), Double(CFloat(val)))
                }
                else if let val = parameter as? Int64 {
                    flag = sqlite3_bind_int64(ps, CInt(i+1), CLongLong(val))
                }
                else if let val = parameter as? Int {
                    flag = sqlite3_bind_int(ps, CInt(i+1), CInt(val))
                }
                else if let val = parameter as? Bool {
                    let num = val ? 1 : 0
                    flag = sqlite3_bind_int(ps, CInt(i+1), CInt(num))
                }
                else if let txt = parameter as? String {
                    flag = sqlite3_bind_text(ps, CInt(i+1), txt, -1, SQLITE_TRANSIENT)
                    //flag = sqlite3_bind_text(ps, CInt(i+1), txt, Int32(txt.utf8.count), SQLITE_TRANSIENT)
                }
                else if let date = parameter as? Date {
                    let dateStr = self.dbDateStr(date: date)
                    flag = sqlite3_bind_text(ps, CInt(i+1), dateStr, -1, SQLITE_TRANSIENT)
                }
                else if let uuid = parameter as? UUID {
                    let uuidStr = uuid.uuidString
                    flag = sqlite3_bind_text(ps, CInt(i+1), uuidStr, -1, SQLITE_TRANSIENT)
                }
                else if let dataValue = parameter as? Data {
                     dataValue.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                        flag = sqlite3_bind_blob(ps, CInt(i+1), bytes.baseAddress, CInt(dataValue.count), SQLITE_TRANSIENT)
                    }
                }
                else if parameter == nil || parameter is NSNull {
                    flag = sqlite3_bind_null(ps,CInt(i+1));
                }
                else
                {
                    log.errorMessage(" SQL Error Stmt No match found for Data Type")
                }
                
                if flag != SQLITE_OK {
                    let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                    let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                    log.errorMessage(" SQL Error bind Stmt : Err[\(errCode)] = \(String(describing: errMsg!)) : Q = \(query) : \nP = \(parameters)\n");
                    let options = ["Message":"SQL Error bind Stmt : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query)) : P = \(String(describing: parameters))"]
                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                }
            }
        }
        else
        {
            let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
            let errCode = Int(sqlite3_errcode(sqlite3dbConn))
            log.errorMessage(" SQL Error prepared Stmt : Err[\(errCode)] = \(String(describing: errMsg!)) : Q = \(query)\n");
            let options = ["Message":"SQL Error prepared Stmt : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query))"]
            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
        }
        
        return ps
    }

    @discardableResult public func executeStatement(_ query: String!, _ args:Any...) -> Bool {
        
        var status : Bool = false
        if(sqlite3dbConn == nil)
        {
            return false
        }
        
        status = self.executeStatement(query, withParams: args)
        return status
    }
    
    public func executeStatementSQL(_ query: String!, _ args:Any...) -> Dictionary<String,Any>! {
        //Create SQL & Params Dictionary for executeStatement for Transactions
        let params:Array<Any> = args
        let sql:String = query
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }
    
    public func getRecordsForQuerySQL(_ query: String!, _ args:Any...) -> Dictionary<String,Any>! {
        //Create SQL & Params Dictionary for getRecordsForQuery for Transactions
        let params:Array<Any> = args
        let sql:String = query
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }
    
    @discardableResult public func executeStatement(_ query: String, withParams parameters: Array<Any>!) -> Bool {
        
        var status : Bool = false
        
        if(sqlite3dbConn == nil)
        {
            return status
        }
        
        queue.sync {
            //Synchronize all accesses
            var ps:OpaquePointer? = nil
            
            if let ps = self.stmt(&ps, forQuery:query, withParams:parameters) {
                let code = sqlite3_step(ps)
                if(code == SQLITE_DONE)
                {
                    status = true
                }
                else
                {
                    status = false
                }
                
                if( !status )
                {
                    let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                    let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                    if(errCode == SQLITE_CORRUPT)
                    {
                        NotificationCenter.default.post(name: SQLITE_DB_CORRUPTED, object: nil)
                    }
                    if(enableLogs)
                    {
                        log.errorMessage(" SQL Error during execute : Err[\(errCode)] = \(String(describing: errMsg!)) : \nQ = \(query)\n : \nP = \(parameters)\n")
                        let options = ["Message":"SQL Error  during execute : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query)) : P = \(String(describing: parameters))"]
                        NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                    }
                }
            }
            sqlite3_finalize(ps)
            sqlite3_exec(sqlite3dbConn, "COMMIT TRANSACTION", nil, nil, nil)
        }
        return status //queue.sync {status}
    }
    
    //Back Ground Queue
    @discardableResult public func executeStatementBG(_ query: String, withParams parameters: Array<Any>!) -> Bool {
        
        var status : Bool = false
        
        if(sqlite3dbConn == nil)
        {
            return status
        }
        
        bgQueue.sync {
            //Synchronize all accesses
            var ps:OpaquePointer? = nil
            
            if let ps = self.stmt(&ps, forQuery:query, withParams:parameters) {
                let code = sqlite3_step(ps)
                if(code == SQLITE_DONE)
                {
                    status = true
                }
                else
                {
                    status = false
                }
                
                if( !status )
                {
                    let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                    let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                    if(errCode == SQLITE_CORRUPT)
                    {
                        NotificationCenter.default.post(name: SQLITE_DB_CORRUPTED, object: nil)
                    }
                    if(enableLogs)
                    {
                        log.errorMessage(" SQL Error during execute : Err[\(errCode)] = \(String(describing: errMsg!)) : \nQ = \(query)\n : \nP = \(parameters)\n")
                        let options = ["Message":"SQL Error  during execute : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query)) : P = \(String(describing: parameters))"]
                        NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                    }
                }
            }
            sqlite3_finalize(ps)
            sqlite3_exec(sqlite3dbConn, "COMMIT TRANSACTION", nil, nil, nil)
        }
        return status //queue.sync {status}
    }

    public func getRecordsForQuery(_ query: String!, _ args:Any...) -> Array<Any> {
        
        var results = [Any]()
        if(sqlite3dbConn == nil)
        {
            return results
        }
        
        results = self.getRecordsForQuery(query, withParams: args)
        return results
    }

    //Back Ground Queue
    public func getRecordsForQueryBG(_ query: String!, _ args:Any...) -> Array<Any> {
        
        var results = [Any]()
        if(sqlite3dbConn == nil)
        {
            return results
        }
        
        results = self.getRecordsForQueryBG(query, withParams: args)
        return results
    }
    
    private func getColumnType(_ ps:OpaquePointer,_ index:CInt)->CInt {
        var type:CInt = 0
        // Column types - http://www.sqlite.org/datatype3.html (section 2.2 table column 1)
        let blobTypes = ["BINARY", "BLOB", "VARBINARY", "DATA"]
        let charTypes = ["CHAR", "CHARACTER", "CLOB", "NATIONAL VARYING CHARACTER", "NATIVE CHARACTER", "NCHAR", "NVARCHAR", "TEXT", "VARCHAR", "VARIANT", "VARYING CHARACTER"]
        let dateTypes = ["DATE", "DATETIME", "TIME", "TIMESTAMP"]
        let intTypes  = ["BIGINT", "BIT", "BOOL", "BOOLEAN", "INT", "INT2", "INT8", "INTEGER", "MEDIUMINT", "SMALLINT", "TINYINT"]
        let nullTypes = ["NULL"]
        let realTypes = ["DECIMAL", "DOUBLE", "DOUBLE PRECISION", "FLOAT", "CGFLOAT", "NUMERIC", "REAL"]
        let uuidTypes = ["UUID"]
        // Determine type of column - http://www.sqlite.org/c3ref/c_blob.html
        let buf = sqlite3_column_decltype(ps, index)
        if buf != nil {
            var tmp = String(validatingUTF8:buf!)!.uppercased()
            if let pos = tmp.range(of:"(") {
                tmp = String(tmp[..<pos.lowerBound])
                //tmp = tmp.substring(to:pos.lowerBound)
            }
            if intTypes.contains(tmp) {
                return SQLITE_INTEGER
            }
            if realTypes.contains(tmp) {
                return SQLITE_FLOAT
            }
            if charTypes.contains(tmp) {
                return SQLITE_TEXT
            }
            if blobTypes.contains(tmp) {
                return SQLITE_BLOB
            }
            if nullTypes.contains(tmp) {
                return SQLITE_NULL
            }
            if dateTypes.contains(tmp) {
                return SQLITE_DATE
            }
            if uuidTypes.contains(tmp) {
                return SQLITE_UUID
            }
                
            //If none of the above has to be text
            return SQLITE_TEXT
        } else {
            // For expressions and sub-queries
            type = sqlite3_column_type(ps, index)
        }
        return type
    }
    
    public func getRecordsForQuery(_ query: String!, withParams parameters: Array<Any>!) -> Array<[String:Any]> {
        //Returns an Array of Dictionaries
        var results = [[String:Any]]()

        if(sqlite3dbConn == nil)
        {
            return results
        }
        queue.sync {

            //Synchronize all accesses
            var ps:OpaquePointer? = nil
            if let ps = self.stmt(&ps, forQuery:query, withParams:parameters)
            {
                let columnCount = sqlite3_column_count(ps)
                while sqlite3_step(ps) == SQLITE_ROW
                {
                    var result = Dictionary<String,AnyObject>()
                    for i in 0..<columnCount
                    {
                        let columnType = self.getColumnType(ps,i)
                        let name = sqlite3_column_name(ps,i)
                        switch columnType {
                        case SQLITE_INTEGER:
                            result[String(validatingUTF8: name!)!] = Int64(sqlite3_column_int64(ps,i)) as AnyObject?
                        case SQLITE_FLOAT:
                            result[String(validatingUTF8: name!)!] = Double(sqlite3_column_double(ps,i)) as AnyObject?
                        case SQLITE_TEXT:
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                result[String(validatingUTF8: name!)!] = String(validatingUTF8:uptr) as AnyObject?
                            }
                        case SQLITE_BLOB:
                            if let bytes = sqlite3_column_blob(ps,i) {
                                result[String(validatingUTF8: name!)!] = Data(bytes:bytes, count:Int(sqlite3_column_bytes(ps,i))) as AnyObject?
                            }
                            else
                            {
                                result[String(validatingUTF8: name!)!] = Data() as AnyObject?
                            }
                        case SQLITE_NULL:
                            result[String(validatingUTF8: name!)!] = String(validatingUTF8:"") as AnyObject?
                        case SQLITE_DATE:
                            //Our defined DATE
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                let dateStr = String(validatingUTF8:uptr)
                                let set = CharacterSet(charactersIn:"-:")
                                if dateStr?.rangeOfCharacter(from:set) != nil {
                                    let date = dbStrDate(date: dateStr ?? "2023-01-01 00:00:00")
                                    result[String(validatingUTF8: name!)!] = date as AnyObject?
                                }
                                else
                                {
                                    log.errorMessage(" SQL Error getRecords Invalid Date ")
                                    let options = ["Message":"SQL Error getRecords Invalid Date"]
                                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                }
                            }
                        case SQLITE_UUID:
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                let uuidStr = String(validatingUTF8:uptr)
                                let set = CharacterSet(charactersIn:"-")
                                if uuidStr?.rangeOfCharacter(from:set) != nil {
                                    let uuid = UUID(uuidString: uuidStr ?? UUID().uuidString)
                                    result[String(validatingUTF8: name!)!] = uuid as AnyObject?
                                }
                                else
                                {
                                    log.errorMessage(" SQL Error getRecords Invalid UUID ")
                                    let options = ["Message":"SQL Error getRecords Invalid UUID"]
                                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                }
                            }
                        default:
                            log.errorMessage(" SQL Error getRecords Invalid column type")
                            let options = ["Message":"SQL Error getRecords Invalid column type"]
                            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                        }
                    }
                    results.append(result)
                }
            }
            else
            {
                let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                log.errorMessage(" SQL Error getRecords : Err[\(errCode)] = \(String(describing: errMsg!)) : Q = \(query!)\n");
                let options = ["Message":"SQL Error  getRecords  : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query))"]
                NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
            }
            sqlite3_finalize(ps)
        }
        return results //queue.sync {results}
    }
    
    //Back Ground Queue
    public func getRecordsForQueryBG(_ query: String!, withParams parameters: Array<Any>!) -> Array<[String:Any]> {
        //Returns an Array of Dictionaries
        var results = [[String:Any]]()

        if(sqlite3dbConn == nil)
        {
            return results
        }
        bgQueue.sync {

            //Synchronize all accesses
            var ps:OpaquePointer? = nil
            if let ps = self.stmt(&ps, forQuery:query, withParams:parameters)
            {
                let columnCount = sqlite3_column_count(ps)
                while sqlite3_step(ps) == SQLITE_ROW
                {
                    var result = Dictionary<String,AnyObject>()
                    for i in 0..<columnCount
                    {
                        let columnType = self.getColumnType(ps,i)
                        let name = sqlite3_column_name(ps,i)
                        switch columnType {
                        case SQLITE_INTEGER:
                            result[String(validatingUTF8: name!)!] = Int64(sqlite3_column_int64(ps,i)) as AnyObject?
                        case SQLITE_FLOAT:
                            result[String(validatingUTF8: name!)!] = Double(sqlite3_column_double(ps,i)) as AnyObject?
                        case SQLITE_TEXT:
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                result[String(validatingUTF8: name!)!] = String(validatingUTF8:uptr) as AnyObject?
                            }
                        case SQLITE_BLOB:
                            if let bytes = sqlite3_column_blob(ps,i) {
                                result[String(validatingUTF8: name!)!] = Data(bytes:bytes, count:Int(sqlite3_column_bytes(ps,i))) as AnyObject?
                            }
                            else
                            {
                                result[String(validatingUTF8: name!)!] = Data() as AnyObject?
                            }
                        case SQLITE_NULL:
                            result[String(validatingUTF8: name!)!] = String(validatingUTF8:"") as AnyObject?
                        case SQLITE_DATE:
                            //Our defined DATE
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                let dateStr = String(validatingUTF8:uptr)
                                let set = CharacterSet(charactersIn:"-:")
                                if dateStr?.rangeOfCharacter(from:set) != nil {
                                    let date = dbStrDate(date: dateStr ?? "2023-01-01 00:00:00")
                                    result[String(validatingUTF8: name!)!] = date as AnyObject?
                                }
                                else
                                {
                                    log.errorMessage(" SQL Error getRecords Invalid Date ")
                                    let options = ["Message":"SQL Error getRecords Invalid Date"]
                                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                }
                            }
                        case SQLITE_UUID:
                            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                let uuidStr = String(validatingUTF8:uptr)
                                let set = CharacterSet(charactersIn:"-")
                                if uuidStr?.rangeOfCharacter(from:set) != nil {
                                    let uuid = UUID(uuidString: uuidStr ?? UUID().uuidString)
                                    result[String(validatingUTF8: name!)!] = uuid as AnyObject?
                                }
                                else
                                {
                                    log.errorMessage(" SQL Error getRecords Invalid UUID ")
                                    let options = ["Message":"SQL Error getRecords Invalid UUID"]
                                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                }
                            }
                        default:
                            log.errorMessage(" SQL Error getRecords Invalid column type")
                            let options = ["Message":"SQL Error getRecords Invalid column type"]
                            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                        }
                    }
                    results.append(result)
                }
            }
            else
            {
                let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                log.errorMessage(" SQL Error getRecords : Err[\(errCode)] = \(String(describing: errMsg!)) : Q = \(query!)\n")
                let options = ["Message":"SQL Error  getRecords  : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query))"]
                NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
            }
            sqlite3_finalize(ps)
        }
        return results //queue.sync {results}
    }
    
    public func getRecordsForQueryTrans(_ sqlAndParamsForTransaction: Array<[String:Any]>!) -> Array<[String:Any]> {
        //Returns an Array of Dictionaries for a Transaction
        //Using this you can append hundreds 'select' statements and execute all of them at once
        //You can create these transactions using getRecordsForQuerySQL
        var results = [[String:Any]]()

        if(sqlite3dbConn == nil)
        {
            return results
        }
        queue.sync {
            //Synchronize all accesses
            for i in 0..<sqlAndParamsForTransaction.count {

                var ps:OpaquePointer? = nil
                sqlite3_exec(sqlite3dbConn, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil)
                let query = sqlAndParamsForTransaction[i][SQL] as! String
                let parameters = sqlAndParamsForTransaction[i][PARAMS] as! Array<Any>
                
                if let ps = self.stmt(&ps, forQuery:query, withParams:parameters)
                {
                    let columnCount = sqlite3_column_count(ps)
                    while sqlite3_step(ps) == SQLITE_ROW
                    {
                        var result = Dictionary<String,AnyObject>()
                        for i in 0..<columnCount
                        {
                            let columnType = self.getColumnType(ps,i)
                            let name = sqlite3_column_name(ps,i)
                            switch columnType {
                            case SQLITE_INTEGER:
                                result[String(validatingUTF8: name!)!] = Int64(sqlite3_column_int64(ps,i)) as AnyObject?
                            case SQLITE_FLOAT:
                                result[String(validatingUTF8: name!)!] = Double(sqlite3_column_double(ps,i)) as AnyObject?
                            case SQLITE_TEXT:
                                if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                    let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                    result[String(validatingUTF8: name!)!] = String(validatingUTF8:uptr) as AnyObject?
                                }
                            case SQLITE_BLOB:
                                if let bytes = sqlite3_column_blob(ps,i) {
                                    result[String(validatingUTF8: name!)!] = Data(bytes:bytes, count:Int(sqlite3_column_bytes(ps,i))) as AnyObject?
                                }
                                else
                                {
                                    result[String(validatingUTF8: name!)!] = Data() as AnyObject?
                                }
                            case SQLITE_NULL:
                                result[String(validatingUTF8: name!)!] = String(validatingUTF8:"") as AnyObject?
                            case SQLITE_DATE:
                                //Our defined DATE
                                if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                    let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                    let dateStr = String(validatingUTF8:uptr)
                                    let set = CharacterSet(charactersIn:"-:")
                                    if dateStr?.rangeOfCharacter(from:set) != nil {
                                        let date = dbStrDate(date: dateStr ?? "2023-01-01 00:00:00")
                                        result[String(validatingUTF8: name!)!] = date as AnyObject?
                                    }
                                    else
                                    {
                                        log.errorMessage(" SQL Error getRecords Invalid Date ")
                                        let options = ["Message":"SQL Error getRecords Invalid Date"]
                                        NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                    }
                                }
                            case SQLITE_UUID:
                                if let ptr = UnsafeRawPointer.init(sqlite3_column_text(ps,i)) {
                                    let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                                    let uuidStr = String(validatingUTF8:uptr)
                                    let set = CharacterSet(charactersIn:"-")
                                    if uuidStr?.rangeOfCharacter(from:set) != nil {
                                        let uuid = UUID(uuidString: uuidStr ?? UUID().uuidString)
                                        result[String(validatingUTF8: name!)!] = uuid as AnyObject?
                                    }
                                    else
                                    {
                                        log.errorMessage(" SQL Error getRecords Invalid UUID ")
                                        let options = ["Message":"SQL Error getRecords Invalid UUID"]
                                        NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                                    }
                                }
                            default:
                                log.errorMessage(" SQL Error getRecords Invalid column type")
                                let options = ["Message":"SQL Error getRecords Invalid column type"]
                                NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                            }
                        }
                        results.append(result)
                    }
                }
                else
                {
                    let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                    let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                    log.errorMessage(" SQL Error getRecords : Err[\(errCode)] = \(String(describing: errMsg!)) : Q = \(query)\n")
                    let options = ["Message":"SQL Error  getRecords  : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query))"]
                    NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                    if(rollBack)
                    {
                        sqlite3_exec(sqlite3dbConn, "ROLLBACK", nil, nil, nil)
                    }
                }
                sqlite3_finalize(ps)
                sqlite3_exec(sqlite3dbConn, "COMMIT TRANSACTION", nil, nil, nil)
            }
        }
        return results //queue.sync {results}
    }
    
    @discardableResult public func executeTransaction(_ sqlAndParamsForTransaction: Array<[String:Any]>!) -> Bool {
        
        var status : Bool = true
        
        if(sqlite3dbConn == nil)
        {
            return status
        }
        
        queue.sync {
            //Synchronize all accesses
            for i in 0..<sqlAndParamsForTransaction.count {

                var ps:OpaquePointer? = nil
                sqlite3_exec(sqlite3dbConn, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil)
                let query = sqlAndParamsForTransaction[i][SQL] as! String
                let parameters = sqlAndParamsForTransaction[i][PARAMS] as! Array<Any>

                if let ps = self.stmt(&ps, forQuery:query, withParams:parameters) {
                    let code = sqlite3_step(ps)
                    if(code == SQLITE_DONE)
                    {
                        status = true
                    }
                    else
                    {
                        status = false
                    }
                    
                    if( !status )
                    {
                        let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                        let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                        if(errCode == SQLITE_CORRUPT)
                        {
                            NotificationCenter.default.post(name: SQLITE_DB_CORRUPTED, object: nil)
                        }
                        if(enableLogs)
                        {
                            log.errorMessage(" SQL Error during executeTransaction : Err[\(errCode)] = \(String(describing: errMsg!)) : \nQ = \(query)\n : \nP = \(parameters)\n")
                            let options = ["Message":"SQL Error during executeTransaction : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query)) : P = \(String(describing: parameters))"]
                            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                        }
                        if(rollBack)
                        {
                            sqlite3_exec(sqlite3dbConn, "ROLLBACK", nil, nil, nil)
                        }
                    }
                }
                sqlite3_finalize(ps)
                sqlite3_exec(sqlite3dbConn, "COMMIT TRANSACTION", nil, nil, nil)
            }
        }
        return status
    }
    
    //Back Ground Queue
    @discardableResult public func executeTransactionBG(_ sqlAndParamsForTransaction: Array<[String:Any]>!) -> Bool {
        
        var status : Bool = true
        
        if(sqlite3dbConn == nil)
        {
            return status
        }
        
        bgQueue.sync {
            //Synchronize all accesses
            for i in 0..<sqlAndParamsForTransaction.count {

                var ps:OpaquePointer? = nil
                sqlite3_exec(sqlite3dbConn, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil)
                let query = sqlAndParamsForTransaction[i][SQL] as! String
                let parameters = sqlAndParamsForTransaction[i][PARAMS] as! Array<Any>

                if let ps = self.stmt(&ps, forQuery:query, withParams:parameters) {
                    let code = sqlite3_step(ps)
                    if(code == SQLITE_DONE)
                    {
                        status = true
                    }
                    else
                    {
                        status = false
                    }
                    
                    if( !status )
                    {
                        let errMsg = String(validatingUTF8:sqlite3_errmsg(sqlite3dbConn))
                        let errCode = Int(sqlite3_errcode(sqlite3dbConn))
                        if(errCode == SQLITE_CORRUPT)
                        {
                            NotificationCenter.default.post(name: SQLITE_DB_CORRUPTED, object: nil)
                        }
                        if(enableLogs)
                        {
                            log.errorMessage(" : SQL Error during executeTransaction : Err[\(errCode)] = \(String(describing: errMsg!)) : \nQ = \(query)\n : \nP = \(parameters)\n")
                            let options = ["Message":"SQL Error during executeTransaction : Err[\(errCode)]","ErrMsg":"\(String(describing: errMsg!))","Query":"Q = \(String(describing:query)) : P = \(String(describing: parameters))"]
                            NotificationCenter.default.post(name: SQLITE_DB_ERR_MESSAGE, object: options)
                        }
                        if(rollBack)
                        {
                            sqlite3_exec(sqlite3dbConn, "ROLLBACK", nil, nil, nil)
                        }
                    }
                }
                sqlite3_finalize(ps)
                sqlite3_exec(sqlite3dbConn, "COMMIT TRANSACTION", nil, nil, nil)
            }
        }
        return status
    }
    
    @discardableResult func copyDBtoDocumentDirectory(copyDBFile:String, toDBFile:String) -> Bool
    {
        var status:Bool = false
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let copyDBPath = (docDir as NSString).appendingPathComponent(copyDBFile)
        let toDBPath = (docDir as NSString).appendingPathComponent(toDBFile)
        
        if (fm.fileExists(atPath:copyDBPath)) {
            do {
                try fm.copyItem(atPath:copyDBPath, toPath:toDBPath)
                status = true
            } catch let error {
                assert(false, ": copyDB : Failed to copy file \(copyDBPath) to \(toDBPath) Error - \(error.localizedDescription)")
                status = false
            }
        }
        return status
    }
    
    @discardableResult func moveDBtoDocumentDirectoryForName(_ fileName:String, dbName:String) -> Bool
    {
        var status:Bool = false
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let path = (docDir as NSString).appendingPathComponent(dbName)
        guard let rp = Bundle.main.resourcePath else { return false }
        let from = (rp as NSString).appendingPathComponent(fileName)
        do {
            try fm.copyItem(atPath:from, toPath:path)
            status = true
        } catch let error {
            assert(false, "DA : moveDB : Failed to move file \(fileName)! to Documents Directory Error - \(error.localizedDescription)")
            status = false
        }
        return status
    }
    
    func pathForFileWithName(fileName:String) -> String
    {
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let path = (docDir as NSString).appendingPathComponent(fileName)
        if (fm.fileExists(atPath:path))  {
            var url = NSURL.fileURL(withPath: docDir)
            url.setTemporaryResourceValue(NSNumber(value:true), forKey: URLResourceKey.isExcludedFromBackupKey)
            return path
        }
        else
        {
            assert(false, "DM : pathFor : Path for file \(fileName)! Not Found ")
            return ""
        }
    }
    
    @discardableResult public func replaceDBinDocumentDirectory(removeDBFile:String, renameDBFile:String) -> Bool
    {
        var status:Bool = false
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let removeDBPath = (docDir as NSString).appendingPathComponent(removeDBFile)
        let renameDBPath = (docDir as NSString).appendingPathComponent(renameDBFile)
        
        do {
            try fm.removeItem(atPath: removeDBPath)
            status = true
        } catch let error {
            assert(false, "DM : replaceDB : Failed to remove file \(removeDBFile)! Error - \(error.localizedDescription)")
            status = false
            return status
        }
        
        do {
            try fm.moveItem(atPath: renameDBPath, toPath: removeDBPath)
            status = true
        } catch let error {
            assert(false, "DM : replaceDB : Failed to move file \(renameDBFile)! Error - \(error.localizedDescription)")
            status = false
            return status
        }
        
        if !(fm.fileExists(atPath:removeDBPath)) {
            assert(false, "DA : replaceDB : Failed to replace file \(removeDBFile) with \(renameDBFile) Error ")
            status = false
        }
        return status
    }
    
    @discardableResult public func replaceDB(replaceDBFile:String, renameDBFile:String) -> Bool
    {
        var status:Bool = false
        let fm = FileManager.default
        let docDir = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        let replaceDBPath = (docDir as NSString).appendingPathComponent(replaceDBFile)
        let renameDBPath = (docDir as NSString).appendingPathComponent(renameDBFile)
        
        do {
            try fm.moveItem(atPath: renameDBPath, toPath: replaceDBPath)
            status = true
        } catch let error {
            assert(false, "DM : replaceDB : Failed to move file \(renameDBFile)! Error - \(error.localizedDescription)")
            status = false
            return status
        }
                
        if !(fm.fileExists(atPath:replaceDBPath)) {
            assert(false, "DA : replaceDB : Failed to replace file \(replaceDBPath) with \(renameDBFile) Error ")
            status = false
        }
        return status
    }
}
