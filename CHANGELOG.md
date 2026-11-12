# Changelog

All notable changes to the `HatangChat` Swift package are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Customers can send videos: the photo library picker offers videos next to photos; a picked clip is loaded as a file and compressed on the device to an H.264 mp4 (720p, then medium quality if still too big) so a typical phone clip fits the new 25 MB video limit. `.mov` files from the file picker are converted the same way. Other files stay at 10 MB.
- Video attachments show as a tile with a frame from the clip and a play glyph; tapping plays it full screen with AVKit. A video still uploading shows its frame, name and size.
- `HatangChatCore`: `Limits.videoBytes` (25 MB), `isVideoUpload(mimeType:name:)`, `attachmentLimit(mimeType:name:)`, `attachmentTooLargeError(mimeType:name:)`, `UploadSource.isVideo`, `UploadSource.maxBytes`, `Attachment.isVideo`; `video/quicktime` (`.mov`) joins `uploadMimeTypes`. `ChatEngine.attach` refuses videos over 25 MB with `video_too_large`.
- `HatangChatStrings.videoTooLarge` ("Video quá lớn (tối đa 25 MB). Hãy quay ngắn hơn hoặc giảm chất lượng." / "Video is too large (max 25 MB). Record a shorter clip or lower the quality."). The memberwise `HatangChatStrings.init` takes it as a new trailing argument with an English default.
- Voice messages, when the site turns them on (`voice_messages` in the site settings): while the text field is empty the send button becomes a mic. Tapping it records (AVAudioRecorder, AAC `.m4a`, mono, 48 kb/s) with a pulsing red dot, an m:ss timer, a trash button to throw it away and the send button to send it; recording stops and sends itself at 2 minutes, and anything under 0.8 s is dropped. The clip is uploaded like any file and sent with no text; the team sees a transcript, the customer does not. The temporary recording is deleted either way.
- Audio attachments (voice notes and other `audio/*` files) play in the bubble with a compact player: play / pause, progress and length (AVPlayer, one clip at a time). Recorded notes are titled "Tin nhắn thoại" / "Voice message".
- `HatangChatCore`: `SiteConfig.voiceMessages` (false when an older gateway does not send it); `VoiceNote` (`maxDuration`, `minDuration`, `fileName(at:)`, `showsMic(voiceMessages:text:hasStaged:enabled:)`, `keeps(duration:)`, `reachedLimit(_:)`, `clock(_:)`, `isVoiceNoteName(_:)`); `isAudioUpload(mimeType:name:)`, `Attachment.isAudio` / `isVoiceNote`, `UploadSource.isAudio` / `isVoiceNote` / `voiceNote(_:at:)`. `audio/webm` and `audio/ogg` join `uploadMimeTypes` (the gateway accepts them).
- `HatangChatStrings.recordVoice`, `recording`, `voiceNote`, `micDenied` (vi/en). The memberwise `HatangChatStrings.init` takes them as new trailing arguments with English defaults, so existing calls still compile.
- **Integrators:** the host app must add `NSMicrophoneUsageDescription` to its Info.plist when voice messages are on (iOS ends the app the first time the mic is used without it), for example "Để gửi tin nhắn thoại cho bộ phận hỗ trợ." / "To send voice messages to support." The microphone permission is asked for the first time the customer taps the mic; if it is refused, the chat shows `micDenied`. The example app's Info.plist has the key.
- The team can edit, recall or remove a file from a message they sent, and the chat follows: the message changes in place, a recalled one shows a muted italic "Tin nhắn đã được thu hồi" / "Message recalled", an edited one gets a small "đã sửa" / "edited" label under it, and a removed file disappears. A change is not a new message: no unread count, read receipt, VoiceOver announcement or conversion.
- `HatangEvent.messageUpdated(MessageDto)`: a message already shown changed (edited, recalled or a file removed). **Hosts with an exhaustive `switch` over `HatangEvent` need a case (or `default`) for it.** `messageReceived` / `messageSent` are no longer emitted again for the same message.
- `MessageDto.isRecalled`, `isEdited`, `editedAt` (from `metadata.recalled`, `metadata.edited`, `metadata.edited_at`).
- `HatangChatStrings.recalled`, `edited` (vi/en). The memberwise `HatangChatStrings.init` takes them as new trailing arguments with English defaults.

### Fixed

- A message sent while the connection was still being made and given up on (10 s timeout, or the connection dropped first) no longer goes out later when the socket comes back. It used to wait in the socket's queue after the bubble showed "failed", so tapping retry delivered it twice on a slow network. Retries keep the message's `client_id`.

## [0.4.1] - 2026-11-03

### Changed

- The package ships a LICENSE file (MIT), and the README opens with what the SDK is and ends with an About Ha Tang section.

## [0.4.0] - 2026-10-31

### Added

- `HatangChat.purchaseToken(userId:)`: the app account token to pass as StoreKit's `.appAccountToken`, so App Store Server Notifications reach the customer in Hatang.
- `HatangChat.reportPurchase(storeProductId:transactionId:signedTransaction:amount:currency:)`: after a successful in-app purchase. With `signedTransaction` (StoreKit 2 `jwsRepresentation`) Hatang verifies it with Apple and records it on the customer; the team also gets a note.
- `ProductCardItem.basePlanId`, `offerId`, `billingPeriod`, `trialDays`; cards in the app carry the App Store price set for the product.

## [0.3.0] - 2026-10-14

### Added
- The chat follows more of the site's widget settings (dashboard: Hỗ trợ → Kênh → chọn site), no code needed: the header subtitle under the site name, the business logo instead of the agents' faces (or the site name's first letter), agent photos in the header, contact buttons (Zalo, Messenger, phone, email) as a row of pills under the header that open the matching app, and the greeting on/off and on-phones switches. A greeting signed by an online agent shows that agent's name under it while the team is online.
- `SiteConfig.header` (`HeaderConfig`, `HeaderProfile`), `SiteConfig.greetingOptions` (`GreetingOptions`, `GreetingSender`), `SiteConfig.contactButtons` (`ContactButton`, `ContactKind`), `SiteConfig.showsGreetingInApp` and `SiteConfig.greetingSigner(online:)` in `HatangChatCore`. All are optional on the wire: older gateways keep today's behaviour.
- `HatangChatStrings.call` ("Gọi điện" / "Call us") and `HatangChatStrings.emailUs` ("Email"). The memberwise `HatangChatStrings.init` takes them as two new trailing arguments.

## [0.2.0] - 2026-10-13

### Fixed
- A paid payment card no longer stays pending until the chat is reopened: the card shows "Paid" and drops the VietQR code, transfer note, expiry and "Pay" as soon as the timeline holds the order's `order_paid` system message or event (the stored card is not updated live).
- Payment cards no longer spin forever on the VietQR code: the gateway serves it as SVG, which iOS cannot decode. The SDK now draws the code natively (CoreImage) from the EMVCo payload, taken from the card (`qr_payload` / `qr.payload`) or the public checkout (`GET /pay/{id}`); a raster `qr_image_url` still works. A failed load shows a retry button.
- Product, order and payment cards no longer repeat their plain-text fallback in a bubble above the card; only the sender's intro line is kept. Unknown card kinds still show the text.

### Added
- `PaymentCard.qrPayload`, `ProductCard.intro`, `PaymentQR` and `cardBubbleText(_:card:)` in `HatangChatCore`.
- `PaidPayments` in `HatangChatCore`: which payment cards of a timeline are paid (own status, or an `order_paid` message / event for the order or payment).

## [0.1.0] - 2026-10-03

### Added
- First release: native iOS SDK for Hatang support chat. SwiftUI chat view, inbox and launcher (plus a UIKit view controller), photo and file attachments, signed identity, APNs push helpers, Vietnamese and English, light and dark themes. `HatangChatCore` (protocol, REST, WebSocket, chat engine) passes the C01–C12 conformance suite.
