//
//  TableName.swift
//  SQLSwiftUIPackage Extensions
//
//  Constants for table names to prevent typos in notifications and queries.
//

import Foundation

/// Constants for SQLite table names.
/// Use these constants in SQLSelectQuery and SQLNotificationCenter
/// to prevent typos and ensure consistent table name strings.
///
/// Example:
///   SQLSelectQuery(TableName.exercise).where("category", .equals, "Chest")
///   SQLNotificationCenter.shared.post(tableChanged: TableName.exercise)
///
public enum TableName {
    public static let exercise        = "Exercise"
    public static let workoutSession  = "WorkoutSession"
    public static let completedSet    = "CompletedSet"
    public static let workoutTemplate = "WorkoutTemplate"
    public static let bodySpecs       = "BodySpecs"
    public static let userProfile     = "UserProfile"
}
