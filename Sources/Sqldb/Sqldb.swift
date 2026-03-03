//
//  Sqldb.swift
//  SQLPackage
//
//  Created by Pat Murphy on 7/27/20.
//  The MIT License (MIT)
// Info : This protocol automatically generates the insert and update SQL queries
// in one line of code, thus elimnating the manual creation of these queries.
// It uses the mirror protocol, and creates an Array of one element Array Dictionary
// so the tables column order is preserved from how the Codable Object creates it.
// The user can also enable sortAlpha true then the SQL will be generated with the
// database column names in alphabetical order.
//

import UIKit


public protocol Sqldb {
    //Every Model requires tableName to be defined for protocol
    var sortAlpha:Bool {set get}
    var tableName:String? {get}
    func getSQLInsert() -> Dictionary<String,Any>!
    func getSQLInsertValid() -> Dictionary<String,Any>!
    func getSQLUpdate(whereItems:String) -> Dictionary<String,Any>!
    func getSQLUpdateValid(whereItems:String) -> Dictionary<String,Any>!
    func getSQLUpsertValid(whereItems:String,forId:String) -> Dictionary<String,Any>!
    func getTableDescription() -> String
}

extension String {
    func contains(word : String) -> Bool
    {
        return self.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
    }
}

public extension Sqldb {
    
    var sortAlpha:Bool {
        get { return false}
        set { sortAlpha = newValue}
    }
    
    //Only works for an initialized Codable Object
    func getTableDescription() -> String {
        let items = getProperties()
        var description = "\r \(tableName!)Obj "

        for array in items {
            let obj = array.first!
            if (obj.value is NSNull)
            {
                let key = obj.key
                description += "\r: \(key) = NULL"
            }
            else
            {
                let value = obj.value
                let key = obj.key
                description += "\r: \(key) = \(value)"
            }
        }
        return description
    }
    
    //Returns SQL update statement with Params, the whereItems are
    //just the table column names used for the SQL where clause.
    func getSQLUpdate(whereItems:String) -> Dictionary<String,Any>! {
        let items = getProperties()
        var params:Array<Any> = []
        var sql:String = "update \(tableName!) set "
        var sqlWhere:String = " where "
        var paramsWhere:Array<Any> = []
        var index:Int = 0
        var whereIndex:Int = 0
        
        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the where clause for update
            if (whereItems.contains(word: obj.key)) {
                if(whereIndex == 0)
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += obj.key + " = ? "
                }
                else
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += "and " + obj.key + " = ? "
                }
                whereIndex += 1
            }
            else
            {
                //Create the rest of the update SQL
                if(index == 0)
                {
                    if (obj.value is NSNull)
                    {
                        sql += obj.key + " = NULL"
                    }
                    else
                    {
                        params.append(obj.value)
                        sql += obj.key + " = ?"
                    }
                }
                else
                {
                    if (obj.value is NSNull)
                    {
                        sql += ", " + obj.key + " = NULL"
                    }
                    else
                    {
                        params.append(obj.value)
                        sql += ", " + obj.key + " = ?"
                    }
                }
                index += 1
            }
        }
        sql += sqlWhere
        params.append(contentsOf:paramsWhere)
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }

    //Like above but skips Null or nil data in SQL
    func getSQLUpdateValid(whereItems:String) -> Dictionary<String,Any>! {
        let items = getProperties()
        var params:Array<Any> = []
        var sql:String = "update \(tableName!) set "
        var sqlWhere:String = " where "
        var paramsWhere:Array<Any> = []
        var index:Int = 0
        var whereIndex:Int = 0
        var hasNull: Bool = false
        
        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the where clause for update
            if (whereItems.contains(word: obj.key)) {
                if(whereIndex == 0)
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += obj.key + " = ? "
                }
                else
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += "and " + obj.key + " = ? "
                }
                whereIndex += 1
            }
            else
            {
                //Create the rest of the update SQL
                if(index == 0)
                {
                    if (obj.value is NSNull)
                    {
                        sql += ""
                        hasNull = true
                    }
                    else
                    {
                        params.append(obj.value)
                        sql += obj.key + " = ?"
                    }
                }
                else
                {
                    if (obj.value is NSNull)
                    {
                        sql += ""
                    }
                    else
                    {
                        params.append(obj.value)
                        if(hasNull)
                        {
                            hasNull = false
                            sql +=  obj.key + " = ?"
                        }
                        else
                        {
                            sql += ", " + obj.key + " = ?"
                        }
                    }
                }
                index += 1
            }
        }
        sql += sqlWhere
        params.append(contentsOf:paramsWhere)
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }

    //Returns SQL insert statement with Params
    func getSQLInsert() -> Dictionary<String,Any>! {
        let items = getProperties()
        var params:Array<Any> = []
        var sql:String = "insert into \(tableName!) ("
        var index:Int = 0
        
        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the column names for the insert SQL
            if(index == 0)
            {
                sql += obj.key
            }
            else
            {
                sql += "," + obj.key
            }
            index += 1
        }
        index = 0
        sql += ") values("
        for array in items {
            //Get our first array element
            let obj = array.first!
            //Create the rest of the insert SQL
            if(index == 0) {
                if (obj.value is NSNull)
                {
                    sql += "NULL"
                }
                else
                {
                    params.append(obj.value)
                    sql += "?"
                }
            }
            else
            {
                if (obj.value is NSNull)
                {
                    sql += ",NULL"
                }
                else
                {
                    params.append(obj.value)
                    sql += ",?"
                }
            }
            index += 1
        }
        sql += ")"
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }
        
    //Like above but skips Null or nil data in SQL
    func getSQLInsertValid() -> Dictionary<String,Any>! {
        let items = getProperties()
        var params:Array<Any> = []
        var sql:String = "insert into \(tableName!) ("
        var index:Int = 0
        var hasNull: Bool = false

        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the column names for the insert SQL
            if(index == 0)
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    sql += obj.key
                }
            }
            else
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    sql += "," + obj.key
                }
            }
            index += 1
        }
        index = 0
        sql += ") values("
        for array in items {
            //Get our first array element
            let obj = array.first!
            //Create the rest of the insert SQL
            if(index == 0) {
                if (obj.value is NSNull)
                {
                    sql += ""
                    hasNull = true
                }
                else
                {
                    params.append(obj.value)
                    sql += "?"
                }
            }
            else
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    params.append(obj.value)
                    if(hasNull)
                    {
                        sql += "?"
                    }
                    else
                    {
                        sql += ",?"
                    }
                }
            }
            index += 1
        }
        sql += ")"
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }
    
    //Like above but skips Null or nil data in SQL
    //Creates an upsert command so you can insert or update in one call without doing a lookup to determine which to use
    //So execution times on this are much faster due to not needing lookup query's
    //Combines insert into with on conflict do update for an upsert
    //creates a 2X size params Array since insert verses update has different params values
    func getSQLUpsertValid(whereItems:String,forId:String) -> Dictionary<String,Any>! {
        let items = getProperties()
        var params:Array<Any> = []
        var sql:String = "insert into \(tableName!) ("
        var sqlWhere:String = " where "
        var paramsWhere:Array<Any> = []
        var index:Int = 0
        var whereIndex:Int = 0
        var hasNull: Bool = false

        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the column names for the insert SQL
            if(index == 0)
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    sql += obj.key
                }
            }
            else
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    sql += "," + obj.key
                }
            }
            index += 1
        }
        index = 0
        sql += ") values("
        for array in items {
            //Get our first array element
            let obj = array.first!
            //Create the rest of the insert SQL
            if(index == 0) {
                if (obj.value is NSNull)
                {
                    sql += ""
                    hasNull = true
                }
                else
                {
                    params.append(obj.value)
                    sql += "?"
                }
            }
            else
            {
                if (obj.value is NSNull)
                {
                    sql += ""
                }
                else
                {
                    params.append(obj.value)
                    if(hasNull)
                    {
                        sql += "?"
                    }
                    else
                    {
                        sql += ",?"
                    }
                }
            }
            index += 1
        }
        sql += ") "
        //Add our Id which must be indexed and unique to work
        sql += "on conflict(" + forId + ") do update  set "
        index = 0
        //Now add update and where clause
        for array in items {
            //Get our first and only array element containing our column dictionary
            let obj = array.first!
            //Create the where clause for update
            if (whereItems.contains(word: obj.key)) {
                if(whereIndex == 0)
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += obj.key + " = ? "
                }
                else
                {
                    paramsWhere.append(obj.value)
                    sqlWhere += "and " + obj.key + " = ? "
                }
                whereIndex += 1
            }
            else
            {
                //Create the rest of the update SQL
                if(index == 0)
                {
                    if (obj.value is NSNull)
                    {
                        sql += ""
                        hasNull = true
                    }
                    else
                    {
                        params.append(obj.value)
                        sql += obj.key + " = ?"
                    }
                }
                else
                {
                    if (obj.value is NSNull)
                    {
                        sql += ""
                    }
                    else
                    {
                        params.append(obj.value)
                        if(hasNull)
                        {
                            hasNull = false
                            sql +=  obj.key + " = ?"
                        }
                        else
                        {
                            sql += ", " + obj.key + " = ?"
                        }
                    }
                }
                index += 1
            }
        }
        sql += sqlWhere
        params.append(contentsOf:paramsWhere)
        let sqlParams = ["SQL":sql,"PARAMS":params] as [String : Any]
        return sqlParams
    }
    
    func getProperties() -> [[String: AnyObject]] {
        //Return an Array of one element Array Dictionary so order is preserved.
        //Otherwise returning a Dictionary will result in a random order and
        //randomized column names in the SQL queries also.
        //Swift Dictionaries are un-ordered data constructs
        var results = [[String:AnyObject]]()
        let mirror = Mirror(reflecting: self)

        // Optional check to make sure we're iterating over a struct or class
        guard let style = mirror.displayStyle, style == .struct || style == .class else {
            return [[:]] // if not return an empty array dictionary
        }

        if(sortAlpha)
        {
            //Sorted by alphabetical key value
            for (label, value) in mirror.children.sorted(by: { var isSorted = false; if let first = $0.label, let second = $1.label {isSorted = first < second }; return isSorted;}) {

                guard let label = label else {
                    continue
                }
                
                if(label == "sortAlpha") {
                    break
                }
                
                //Skip tableName and sortAlpha since they aren't needed for queries
                if(label != "tableName" && label != "sortAlpha")
                {
                    if let values:AnyObject = value as? AnyObject  {
                        let sqlDic = [label:values]
                        results.append(sqlDic)
                    }
                }
            }
        }
        else
        {
            //Original order from object
            for (label, value) in mirror.children {

                guard let label = label else {
                    continue
                }
                
                if(label == "sortAlpha") {
                    break
                }
                
                //Skip tableName and sortAlpha since they aren't needed for queries
                if(label != "tableName" && label != "sortAlpha")
                {
                    if let values:AnyObject = value as? AnyObject {
                        let sqlDic = [label:values]
                        results.append(sqlDic)
                    }
                }
            }
        }
        return results
    }
    
}

