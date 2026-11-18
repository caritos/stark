//
//  ContactsBirthYears.swift
//  Stark
//
//  Read-only Contacts lookup of birth years for the Birthdays calendar's events. Fetches only
//  the birthday field, never stores or logs it. Any missing access or error means no years, and
//  the agenda shows the cake without an age.
//

import Contacts
import Foundation
import StarkKit

nonisolated struct ContactsBirthYears: BirthYearLookup {
    func birthYears(forContactIDs ids: Set<String>) async -> [String: Int] {
        guard !ids.isEmpty else { return [:] }
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            // The one prompt: the first time Stark loads a birthday from a calendar the owner shows
            // (`AppleOverlayModel` calls this only for those, one lookup at a time).
            _ = try? await store.requestAccess(for: .contacts)
        }
        // .limited (iOS 18) still answers for the contacts the person shared; the rest are absent.
        let status = CNContactStore.authorizationStatus(for: .contacts)
        var allowed = status == .authorized
        if #available(iOS 18.0, macCatalyst 18.0, *), status == .limited { allowed = true }
        guard allowed else { return [:] }
        return await Task.detached {
            do {
                let contacts = try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(withIdentifiers: Array(ids)),
                    keysToFetch: [CNContactBirthdayKey as CNKeyDescriptor])
                var result: [String: Int] = [:]
                for contact in contacts where contact.birthday != nil {
                    if let year = BirthYear.year(from: contact.birthday) { result[contact.identifier] = year }
                }
                return result
            } catch {
                return [:]
            }
        }.value
    }
}
