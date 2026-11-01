import Testing
import Foundation
@testable import StarkKit

struct PlanLayoutTests {
    let cal = Calendar(identifier: .gregorian)
    var day: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }
    func block(_ h: Int, _ m: Int = 0, minutes: Int = 30, id: String = UUID().uuidString) -> PlanBlock {
        PlanBlock(id: id, reminderID: "r", occurrence: day, start: at(h, m), minutes: minutes)
    }

    @Test func snapsToQuarterHour() {
        #expect(PlanLayout.snap(at(9, 7)) == at(9, 0))
        #expect(PlanLayout.snap(at(9, 8)) == at(9, 15))
    }

    @Test func clampsAtMidnight() throws {
        let placed = try #require(PlanLayout.place(block(23, 50), among: [], day: day))
        #expect(placed.start == at(23, 30))
        #expect(placed.minutes == 30)
    }

    @Test func clampsAtDayStart() throws {
        let early = PlanBlock(reminderID: "r", occurrence: day, start: at(0, 0).addingTimeInterval(-3600), minutes: 30)
        let placed = try #require(PlanLayout.place(early, among: [], day: day))
        #expect(placed.start == at(0, 0))
    }

    @Test func freeDropIsSnappedOnly() throws {
        let placed = try #require(PlanLayout.place(block(9, 7), among: [], day: day))
        #expect(placed.start == at(9, 0))
    }

    @Test func overlapMovesToNearestFreeSlot() throws {
        let others = [block(8, 0, minutes: 60), block(9, 0), block(9, 30)]
        let placed = try #require(PlanLayout.place(block(9, 15), among: others, day: day))
        #expect(placed.start == at(10, 0))
    }

    @Test func equalDistanceTiePrefersEarlierSlot() throws {
        // 8:30 and 10:00 are both 45 minutes from 9:15: the earlier wins.
        let others = [block(9, 0), block(9, 30)]
        let placed = try #require(PlanLayout.place(block(9, 15), among: others, day: day))
        #expect(placed.start == at(8, 30))
    }

    @Test func adjacentBlocksDoNotOverlap() throws {
        let placed = try #require(PlanLayout.place(block(9, 30), among: [block(9, 0)], day: day))
        #expect(placed.start == at(9, 30))
    }

    @Test func refusedWhenDayFull() {
        let full = PlanBlock(reminderID: "x", occurrence: day, start: at(0, 0), minutes: 24 * 60)
        #expect(PlanLayout.place(block(9, 0), among: [full], day: day) == nil)
    }

    @Test func refusedWhenNoGapBigEnough() {
        // Only 15 minute gaps remain.
        var others: [PlanBlock] = []
        var m = 0
        while m < 24 * 60 {
            others.append(PlanBlock(reminderID: "x", occurrence: day, start: at(0, 0).addingTimeInterval(TimeInterval(m * 60)), minutes: 45))
            m += 60
        }
        #expect(PlanLayout.place(block(9, 0), among: others, day: day) == nil)
    }

    @Test func eventsDoNotBlockPlacement() throws {
        // Only plan blocks are inputs; with none, the drop lands where it was dropped.
        let placed = try #require(PlanLayout.place(block(9, 0), among: [], day: day))
        #expect(placed.start == at(9, 0))
    }

    @Test func placeKeepsIdentityAndMinutes() throws {
        let b = block(9, 0, minutes: 45, id: "keep")
        let placed = try #require(PlanLayout.place(b, among: [], day: day))
        #expect(placed.id == "keep")
        #expect(placed.minutes == 45)
        #expect(placed.reminderID == "r")
    }

    @Test func resizeStopsAtNextBlock() {
        let r = PlanLayout.resized(block(9, 0), toMinutes: 120, among: [block(10, 0)], day: day)
        #expect(r.minutes == 60)
        #expect(r.start == at(9, 0))
    }

    @Test func resizeStopsAtMidnight() {
        let r = PlanLayout.resized(block(23, 0), toMinutes: 120, among: [], day: day)
        #expect(r.minutes == 60)
    }

    @Test func resizeSnapsToQuarterHour() {
        #expect(PlanLayout.resized(block(9, 0), toMinutes: 38, among: [], day: day).minutes == 45)
        #expect(PlanLayout.resized(block(9, 0), toMinutes: 37, among: [], day: day).minutes == 30)
    }

    @Test func resizeNeverBelowFifteen() {
        #expect(PlanLayout.resized(block(9, 0), toMinutes: 0, among: [], day: day).minutes == 15)
        #expect(PlanLayout.resized(block(9, 0), toMinutes: -30, among: [], day: day).minutes == 15)
    }

    @Test func resizeIgnoresEarlierBlocks() {
        let r = PlanLayout.resized(block(9, 0), toMinutes: 60, among: [block(8, 0)], day: day)
        #expect(r.minutes == 60)
    }
}
