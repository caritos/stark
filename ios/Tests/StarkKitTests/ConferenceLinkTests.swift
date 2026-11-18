import Foundation
import Testing
@testable import StarkKit

@Suite struct ConferenceLinkTests {
    private func detect(url: String? = nil, location: String? = nil, notes: String? = nil) -> ConferenceLink? {
        ConferenceLinkDetector.detect(url: url, location: location, notes: notes)
    }

    @Test func zoomLinkInUrlField() {
        let link = detect(url: "https://us02web.zoom.us/j/123456789?pwd=abc")
        #expect(link?.provider == .zoom)
        #expect(link?.title == "Join Zoom")
        #expect(link?.accessibilityLabel == "Join Zoom meeting")
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
    }

    @Test func zoomPaths() {
        for path in ["/j/1", "/my/room", "/s/1", "/w/1"] {
            #expect(detect(url: "https://zoom.us\(path)")?.provider == .zoom, "\(path)")
        }
    }

    @Test func bareZoomWithoutSchemeOrPathIsNotALink() {
        #expect(detect(notes: "call me on zoom.us") == nil)
        #expect(detect(url: "https://zoom.us") == nil)
        #expect(detect(url: "https://zoom.us/") == nil)
        #expect(detect(url: "https://zoom.us/pricing") == nil)
    }

    @Test func hostSuffixAttacksAreRejected() {
        #expect(detect(url: "https://notzoom.us/j/1") == nil)
        #expect(detect(url: "https://zoom.us.evil.com/j/1") == nil)
        #expect(detect(url: "https://evil.com/zoom.us/j/1") == nil)
        #expect(detect(url: "https://meet.google.com.evil.com/abc-defg-hij") == nil)
        #expect(detect(url: "https://user@evil.com/j/1#zoom.us") == nil)
    }

    @Test func onlyHttpsIsAccepted() {
        #expect(detect(url: "http://zoom.us/j/1") == nil)
        #expect(detect(url: "javascript:alert(1)//zoom.us/j/1") == nil)
        #expect(detect(url: "zoommtg://zoom.us/join?confno=1") == nil)
        #expect(detect(url: "ftp://zoom.us/j/1") == nil)
    }

    @Test func trailingPunctuationInNotesIsTrimmed() {
        for text in ["Join: https://zoom.us/j/123.", "(https://zoom.us/j/123)", "<https://zoom.us/j/123>",
                     "https://zoom.us/j/123, thanks", "https://zoom.us/j/123;"] {
            #expect(detect(notes: text)?.url.absoluteString == "https://zoom.us/j/123", "\(text)")
        }
    }

    @Test func uppercaseSchemeAndHost() {
        let link = detect(url: "HTTPS://ZOOM.US/J/123")
        #expect(link?.provider == .zoom)
    }

    @Test func urlFieldBeatsLocationBeatsNotes() {
        let all = detect(url: "https://zoom.us/j/1", location: "https://meet.google.com/abc-defg-hij",
                         notes: "https://teams.microsoft.com/l/meetup-join/x")
        #expect(all?.provider == .zoom)
        let noUrl = detect(location: "https://meet.google.com/abc-defg-hij", notes: "https://zoom.us/j/1")
        #expect(noUrl?.provider == .googleMeet)
        let notesOnly = detect(notes: "https://zoom.us/j/1")
        #expect(notesOnly?.provider == .zoom)
    }

    @Test func firstSupportedLinkWinsInOneField() {
        let link = detect(notes: "Agenda https://example.com/doc then https://zoom.us/j/1 or https://meet.google.com/abc-defg-hij")
        #expect(link?.provider == .zoom)
    }

    @Test func nonConferenceUrlFieldDoesNotHideZoomInNotes() {
        let link = detect(url: "https://example.com/agenda", notes: "Dial in: https://zoom.us/j/99")
        #expect(link?.provider == .zoom)
        #expect(link?.url.absoluteString == "https://zoom.us/j/99")
        #expect(detect(url: "https://example.com/agenda") == nil)
    }

    @Test func googleMeetInLocation() {
        let link = detect(location: "https://meet.google.com/abc-defg-hij")
        #expect(link?.provider == .googleMeet)
        #expect(link?.title == "Join Google Meet")
        #expect(detect(url: "https://meet.google.com/") == nil)
    }

    @Test func teamsWithQueryString() {
        let url = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d"
        let link = detect(notes: "Join \(url)")
        #expect(link?.provider == .teams)
        #expect(link?.url.absoluteString == url)
        #expect(detect(url: "https://teams.microsoft.com/meet/123456?p=abc")?.provider == .teams)
        #expect(detect(url: "https://teams.live.com/meet/123456")?.provider == .teams)
        #expect(detect(url: "https://teams.microsoft.com/l/chat/0/0") == nil)
    }

    @Test func webexAndFaceTime() {
        #expect(detect(url: "https://acme.webex.com/meet/jane")?.provider == .webex)
        #expect(detect(url: "https://webex.com/meet/jane")?.provider == .webex)
        #expect(detect(url: "https://acme.webex.com") == nil)
        #expect(detect(url: "https://facetime.apple.com/join#v=1&p=abc")?.provider == .faceTime)
        #expect(detect(url: "https://facetime.apple.com/") == nil)
    }

    @Test func emptyAndNilInputs() {
        #expect(detect() == nil)
        #expect(detect(url: "", location: "", notes: "") == nil)
    }
}
