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

    // MARK: performance (invitations come from outsiders)

    private func seconds(_ body: () -> Void) -> Double {
        let start = Date()
        body()
        return Date().timeIntervalSince(start)
    }

    @Test func pathologicalNotesFinishQuickly() {
        let colonSlash = String(repeating: "a", count: 20_000) + ":/"
        #expect(seconds { _ = detect(notes: colonSlash) } < 1)
        let hex = String(repeating: "0123456789abcdef", count: 1_280)
        #expect(seconds { _ = detect(notes: hex) } < 1)
        let links = String(repeating: "https://example.com/x ", count: 30_000)
        #expect(links.utf16.count > 600_000)
        #expect(seconds { _ = detect(notes: links) } < 1)
        let bigWithLinkAtEnd = String(repeating: "x", count: 1_000_000) + " https://zoom.us/j/1"
        #expect(seconds { _ = detect(notes: bigWithLinkAtEnd) } < 1)
        // Only the first 20,000 UTF-16 units are scanned.
        #expect(detect(notes: bigWithLinkAtEnd) == nil)
    }

    @Test func linkGluedToTextIsFound() {
        #expect(detect(notes: "Join Zoom Meetinghttps://zoom.us/j/1")?.url.absoluteString == "https://zoom.us/j/1")
    }

    // MARK: hosts and userinfo

    @Test func userinfoPortlessOddHostsAreRejected() {
        #expect(detect(url: "https://user@zoom.us/j/1") == nil)
        #expect(detect(url: "https://user:pw@zoom.us/j/1") == nil)
        #expect(detect(url: "https://zoom.us%2eevil.com/j/1") == nil)
        #expect(detect(url: "https://zo%6fm.us/j/1") == nil)
        #expect(detect(url: "https://zoom_.us/j/1") == nil)
        #expect(detect(url: "https://.zoom.us/j/1") == nil)
    }

    @Test func trailingDotHostIsAccepted() {
        #expect(detect(url: "https://zoom.us./j/1")?.provider == .zoom)
    }

    @Test func zoomGov() {
        #expect(detect(url: "https://us06web.zoomgov.com/j/1")?.provider == .zoom)
    }

    // MARK: trimming and splitting

    @Test func moreTrailingPunctuationAndQuotes() {
        for text in ["*https://zoom.us/j/1*", "_https://zoom.us/j/1_", "\u{201C}https://zoom.us/j/1\u{201D}",
                     "\u{2018}https://zoom.us/j/1\u{2019}", "https://zoom.us/j/1\u{2026}", "https://zoom.us/j/1\u{3002}",
                     "\u{FF08}https://zoom.us/j/1\u{FF09}", "https://zoom.us/j/1\u{FF0C}next"] {
            #expect(detect(notes: text)?.url.absoluteString == "https://zoom.us/j/1", "\(text)")
        }
    }

    @Test func commaJoinedLinksSplitAndFirstWins() {
        let link = detect(notes: "https://zoom.us/j/1,https://meet.google.com/abc-defg-hij")
        #expect(link?.url.absoluteString == "https://zoom.us/j/1")
        let second = detect(notes: "https://example.com/a,https://zoom.us/j/2")
        #expect(second?.url.absoluteString == "https://zoom.us/j/2")
    }

    @Test func zeroWidthSpaceEndsALink() {
        #expect(detect(notes: "https://zoom.us/j/1\u{200B}https://meet.google.com/abc-defg-hij")?.url.absoluteString == "https://zoom.us/j/1")
    }

    // MARK: tighter providers

    @Test func webexOnlyForMeetingPaths() {
        for path in ["/meet/jane", "/join/jane", "/wbxmjs/joinservice/x", "/webappng/sites/a/meeting/x", "/j.php?MTID=1"] {
            #expect(detect(url: "https://acme.webex.com\(path)")?.provider == .webex, "\(path)")
        }
        #expect(detect(url: "https://www.webex.com/pricing") == nil)
        #expect(detect(url: "https://help.webex.com/en-us/article") == nil)
    }

    @Test func meetOnlyForCodesAndLookup() {
        #expect(detect(url: "https://meet.google.com/abc-defg-hij")?.provider == .googleMeet)
        #expect(detect(url: "https://meet.google.com/lookup/abc123")?.provider == .googleMeet)
        #expect(detect(url: "https://meet.google.com/landing") == nil)
        #expect(detect(url: "https://meet.google.com/new") == nil)
    }

    @Test func teamsNeedsASegmentAfterThePrefix() {
        #expect(detect(url: "https://teams.microsoft.com/l/meetup-join/19%3ax/0")?.provider == .teams)
        #expect(detect(url: "https://teams.microsoft.com/meet/123")?.provider == .teams)
        #expect(detect(url: "https://teams.microsoft.com/l/meetup-join") == nil)
        #expect(detect(url: "https://teams.microsoft.com/l/meetup-joinevil/x") == nil)
        #expect(detect(url: "https://teams.microsoft.com/meet/") == nil)
        #expect(detect(url: "https://teams.live.com/meet/") == nil)
    }
}
