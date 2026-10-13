# Changelog

All notable changes to the `HatangChat` Swift package are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Payment cards no longer spin forever on the VietQR code: the gateway serves it as SVG, which iOS cannot decode. The SDK now draws the code natively (CoreImage) from the EMVCo payload, taken from the card (`qr_payload` / `qr.payload`) or the public checkout (`GET /pay/{id}`); a raster `qr_image_url` still works. A failed load shows a retry button.
- Product, order and payment cards no longer repeat their plain-text fallback in a bubble above the card; only the sender's intro line is kept. Unknown card kinds still show the text.

### Added
- `PaymentCard.qrPayload`, `ProductCard.intro`, `PaymentQR` and `cardBubbleText(_:card:)` in `HatangChatCore`.

## [0.1.0] - 2026-10-03

### Added
- First release: native iOS SDK for Hatang support chat. SwiftUI chat view, inbox and launcher (plus a UIKit view controller), photo and file attachments, signed identity, APNs push helpers, Vietnamese and English, light and dark themes. `HatangChatCore` (protocol, REST, WebSocket, chat engine) passes the C01–C12 conformance suite.
