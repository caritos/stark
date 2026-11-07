import Testing
@testable import StarkClaudeCore

@Suite struct DeviceResolverTests {
    @Test func resolvesTheOnlyAvailablePairedIPhone() throws {
        let r = FakeRunner()
        #expect(try DeviceResolver(runner: r, environment: [:]).resolve() == "AAAA-1111")
        #expect(r.calls.first?.arguments.prefix(3) == ["devicectl", "list", "devices"])
    }
    @Test func honoursEnvByNameIdentifierOrUDID() throws {
        for key in ["Spare iPhone", "BBBB-2222", "0000-UDID2"] {
            let r = FakeRunner(); r.devicesJSON = Fixtures.twoIPhones
            #expect(try DeviceResolver(runner: r, environment: ["STARK_DEVICE": key]).resolve() == "BBBB-2222")
        }
    }
    @Test func envMatchingNothingIsNoDevice() {
        let r = FakeRunner()
        #expect(throws: CLIError.noDevice) {
            try DeviceResolver(runner: r, environment: ["STARK_DEVICE": "Nina’s iPad"]).resolve()
        }
    }
    @Test func noDevice() {
        let r = FakeRunner(); r.devicesJSON = Fixtures.none
        #expect(throws: CLIError.noDevice) { try DeviceResolver(runner: r, environment: [:]).resolve() }
    }
    @Test func ambiguous() {
        let r = FakeRunner(); r.devicesJSON = Fixtures.twoIPhones
        #expect(throws: CLIError.ambiguousDevice(["Eladio’s iPhone", "Spare iPhone"])) {
            try DeviceResolver(runner: r, environment: [:]).resolve()
        }
    }
    @Test func unreadableListFailsClosed() {
        let r = FakeRunner(); r.devicesJSON = "not json"
        #expect(throws: CLIError.self) { try DeviceResolver(runner: r, environment: [:]).resolve() }
    }
}
