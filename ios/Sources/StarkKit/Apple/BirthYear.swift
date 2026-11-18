// ios/Sources/StarkKit/Apple/BirthYear.swift
import Foundation

public enum BirthYear {
    /// The birth year in a contact's birthday components; nil without components or a year, and for
    /// years before 1900 (Contacts stores a placeholder year such as 1604 when none was entered).
    public static func year(from components: DateComponents?) -> Int? {
        guard let year = components?.year, year >= 1900 else { return nil }
        return year
    }
}

/// Looks up birth years in Contacts. Returns `[:]` when access is missing; never throws.
public protocol BirthYearLookup: Sendable {
    func birthYears(forContactIDs ids: Set<String>) async -> [String: Int]
}
