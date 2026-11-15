// ios/Tests/StarkKitTests/DefaultDestinationTests.swift
import Foundation
import Testing
@testable import StarkKit

@Suite("DefaultDestination")
struct DefaultDestinationTests {
    private func cal(_ id: String, list: Bool = false, writable: Bool = true) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: nil, isReminderList: list,
                          isWritable: writable)
    }

    private var all: [AppleCalendarInfo] {
        [cal("home"), cal("work"), cal("holidays", writable: false),
         cal("inbox", list: true), cal("groceries", list: true), cal("shared", list: true, writable: false)]
    }

    @Test func choicesAreWritableOnlyAndOfTheRightKind() {
        #expect(DefaultDestination.choices(all, reminderLists: false).map(\.id) == ["home", "work"])
        #expect(DefaultDestination.choices(all, reminderLists: true).map(\.id) == ["groceries", "inbox"])
    }

    @Test func storedChoiceWinsWhenStillWritable() {
        let r = DefaultDestination.resolve(stored: "work", systemDefault: "home", in: all, reminderLists: false)
        #expect(r == DefaultDestination.Resolution(id: "work", persist: false))
    }

    @Test func firstUseTakesTheSystemDefaultAndPersistsIt() {
        let r = DefaultDestination.resolve(stored: nil, systemDefault: "inbox", in: all, reminderLists: true)
        #expect(r == DefaultDestination.Resolution(id: "inbox", persist: true))
    }

    @Test func readOnlySystemDefaultFallsBackToTheFirstWritable() {
        let r = DefaultDestination.resolve(stored: nil, systemDefault: "holidays", in: all, reminderLists: false)
        #expect(r == DefaultDestination.Resolution(id: "home", persist: true))
    }

    @Test func missingStoredChoiceFallsBackWithoutForgettingIt() {
        // The stored calendar may be on an account still syncing: use another for now, keep the choice.
        let r = DefaultDestination.resolve(stored: "gone", systemDefault: "work", in: all, reminderLists: false)
        #expect(r == DefaultDestination.Resolution(id: "work", persist: false))
    }

    @Test func storedChoiceOfTheWrongKindIsNotUsed() {
        let r = DefaultDestination.resolve(stored: "home", systemDefault: nil, in: all, reminderLists: true)
        #expect(r == DefaultDestination.Resolution(id: "groceries", persist: false))
    }

    @Test func nothingWritableResolvesToNil() {
        let readOnly = [cal("holidays", writable: false), cal("shared", list: true, writable: false)]
        #expect(DefaultDestination.resolve(stored: "holidays", systemDefault: "holidays", in: readOnly,
                                           reminderLists: false).id == nil)
        #expect(DefaultDestination.resolve(stored: nil, systemDefault: nil, in: [], reminderLists: true).id == nil)
    }

    @Test func problemNamesWhatIsMissing() {
        #expect(DefaultDestination.problem(calendarID: "a", listID: "b") == nil)
        #expect(DefaultDestination.problem(calendarID: nil, listID: "b")
            == "No calendar Stark can add events to. Add or allow one in Apple Calendar, then choose it in Settings.")
        #expect(DefaultDestination.problem(calendarID: "a", listID: nil)
            == "No reminder list Stark can add to. Add one in Apple Reminders, then choose it in Settings.")
        #expect(DefaultDestination.problem(calendarID: nil, listID: nil)
            == "No calendar or reminder list Stark can add to. Add one in Apple Calendar or Reminders, then choose it in Settings.")
    }
}

@Suite("AppleSettings default lock")
struct AppleSettingsDefaultLockTests {
    @Test func defaultCalendarAndListAreLockedOn() {
        #expect(AppleSettings.isLockedOn("home", calendarID: "home", listID: "inbox"))
        #expect(AppleSettings.isLockedOn("inbox", calendarID: "home", listID: "inbox"))
        #expect(!AppleSettings.isLockedOn("work", calendarID: "home", listID: "inbox"))
        #expect(!AppleSettings.isLockedOn("work", calendarID: nil, listID: nil))
    }
}
