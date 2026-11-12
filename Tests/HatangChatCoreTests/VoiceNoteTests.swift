import XCTest
@testable import HatangChatCore

final class VoiceNoteTests: XCTestCase {
    private func config(_ text: String) throws -> SiteConfig {
        SiteConfig(json: try XCTUnwrap(JSONValue.parse(text)?.objectValue))
    }

    func testSiteConfigDecodesVoiceMessagesAndOlderGatewaysMeanOff() throws {
        XCTAssertTrue(try config(#"{"site_id":"s","voice_messages":true}"#).voiceMessages)
        XCTAssertFalse(try config(#"{"site_id":"s","voice_messages":false}"#).voiceMessages)
        // Absent (older gateways) or malformed: off.
        XCTAssertFalse(try config(#"{"site_id":"s"}"#).voiceMessages)
        XCTAssertFalse(try config(#"{"site_id":"s","voice_messages":"yes"}"#).voiceMessages)
        XCTAssertFalse(SiteConfig().voiceMessages)
        // Round trip; an older payload stays without the key.
        let on = try config(#"{"site_id":"s","voice_messages":true}"#)
        XCTAssertEqual(on.toJSON()["voice_messages"], .bool(true))
        XCTAssertTrue(SiteConfig(json: on.toJSON()).voiceMessages)
        XCTAssertNil(try config(#"{"site_id":"s"}"#).toJSON()["voice_messages"])
        var off = on
        off.voiceMessages = false
        XCTAssertEqual(off.toJSON()["voice_messages"], .bool(false))
        XCTAssertFalse(BootstrapResponse(json: bootstrapFixture()).config.voiceMessages)
    }

    func testMicShowsOnlyWhenAllowedEnabledAndTheFieldIsEmpty() {
        XCTAssertTrue(VoiceNote.showsMic(voiceMessages: true, text: ""))
        XCTAssertTrue(VoiceNote.showsMic(voiceMessages: true, text: "  \n "))
        XCTAssertFalse(VoiceNote.showsMic(voiceMessages: true, text: "hi"))
        XCTAssertFalse(VoiceNote.showsMic(voiceMessages: false, text: ""))
        XCTAssertFalse(VoiceNote.showsMic(voiceMessages: true, text: "", hasStaged: true))
        XCTAssertFalse(VoiceNote.showsMic(voiceMessages: true, text: "", enabled: false))
    }

    func testMicNeedsTheAppsMicrophoneUsageDescription() {
        XCTAssertTrue(VoiceNote.appDeclaresMicrophone(["NSMicrophoneUsageDescription": "Gửi tin nhắn thoại cho shop"]))
        XCTAssertFalse(VoiceNote.appDeclaresMicrophone([:]))
        XCTAssertFalse(VoiceNote.appDeclaresMicrophone(["NSMicrophoneUsageDescription": "  "]))
        XCTAssertFalse(VoiceNote.appDeclaresMicrophone(nil))
    }

    func testDurationRulesAndClock() {
        XCTAssertEqual(VoiceNote.maxDuration, 120)
        XCTAssertFalse(VoiceNote.keeps(duration: 0.79))
        XCTAssertTrue(VoiceNote.keeps(duration: 0.8))
        XCTAssertTrue(VoiceNote.keeps(duration: 45))
        XCTAssertFalse(VoiceNote.reachedLimit(119.9))
        XCTAssertTrue(VoiceNote.reachedLimit(120))
        XCTAssertEqual(VoiceNote.clock(0), "0:00")
        XCTAssertEqual(VoiceNote.clock(7.9), "0:07")
        XCTAssertEqual(VoiceNote.clock(65), "1:05")
        XCTAssertEqual(VoiceNote.clock(120), "2:00")
        XCTAssertEqual(VoiceNote.clock(-3), "0:00")
        XCTAssertEqual(VoiceNote.clock(.nan), "0:00")
    }

    func testFileNamingAndTheUploadSource() {
        let at = Date(timeIntervalSince1970: 1_790_000_000.123)
        XCTAssertEqual(VoiceNote.fileName(at: at), "voice-1790000000123.m4a")
        let s = UploadSource.voiceNote(Data([1, 2, 3]), at: at)
        XCTAssertEqual(s.name, "voice-1790000000123.m4a")
        XCTAssertEqual(s.mimeType, "audio/mp4")
        XCTAssertTrue(uploadMimeTypes.contains(s.mimeType))
        XCTAssertTrue(s.isAudio)
        XCTAssertTrue(s.isVoiceNote)
        XCTAssertFalse(s.isVideo)
        XCTAssertEqual(s.maxBytes, Limits.attachmentBytes)
    }

    func testAudioAndVoiceNoteDetection() {
        XCTAssertTrue(Attachment(name: "voice-1.m4a", type: "audio/mp4").isVoiceNote)
        XCTAssertTrue(Attachment(name: "Voice-1.webm", type: "audio/webm").isVoiceNote)
        XCTAssertTrue(Attachment(name: "voice-1.webm", type: "application/octet-stream").isVoiceNote)
        XCTAssertTrue(Attachment(name: "song.mp3", type: "audio/mpeg").isAudio)
        XCTAssertFalse(Attachment(name: "song.mp3", type: "audio/mpeg").isVoiceNote)
        XCTAssertTrue(Attachment(name: "memo.m4a", type: "application/octet-stream").isAudio)
        XCTAssertFalse(Attachment(name: "clip.webm", type: "video/webm").isAudio)
        XCTAssertFalse(Attachment(name: "voice-over.mp4", type: "video/mp4").isAudio)
        XCTAssertFalse(Attachment(name: "voice-notes.pdf", type: "application/pdf").isVoiceNote)
        XCTAssertFalse(Attachment(name: "a.png", type: "image/png").isAudio)
        XCTAssertEqual(mimeTypeForName("voice-1.ogg"), "audio/ogg")
        XCTAssertTrue(uploadMimeTypes.contains("audio/webm"))
        XCTAssertTrue(uploadMimeTypes.contains("audio/ogg"))
    }

    func testVoiceStringsInBothLanguages() {
        XCTAssertEqual(HatangChatStrings.vi.recordVoice, "Ghi âm tin nhắn thoại")
        XCTAssertEqual(HatangChatStrings.vi.recording, "Đang ghi âm…")
        XCTAssertEqual(HatangChatStrings.vi.voiceNote, "Tin nhắn thoại")
        XCTAssertEqual(HatangChatStrings.vi.micDenied, "Không dùng được micro. Hãy cho phép ứng dụng dùng micro trong Cài đặt.")
        XCTAssertEqual(HatangChatStrings.en.recordVoice, "Record a voice message")
        XCTAssertEqual(HatangChatStrings.en.recording, "Recording…")
        XCTAssertEqual(HatangChatStrings.en.voiceNote, "Voice message")
        XCTAssertEqual(HatangChatStrings.en.micDenied, "The microphone is not available. Allow the app to use it in Settings.")
    }
}
