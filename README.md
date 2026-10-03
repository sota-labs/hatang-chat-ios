# Hatang Chat for iOS (`HatangChat`)

Native support chat for iOS apps: SwiftUI chat view, inbox and launcher, a UIKit view controller, signed identity, attachments, push helpers. Talks the Hatang realtime protocol directly; no dependencies beyond the system frameworks.

- `HatangChatCore`: Foundation only (protocol, REST, WebSocket, `ChatEngine` actor). Builds and tests on macOS too.
- `HatangChat`: the iOS facade and UI.
- `Example/`: demo app (`make project && open HatangChatExample.xcodeproj`), defaults to the local gateway at `http://localhost:3002`.

Requirements: iOS 17+, Xcode 16+ (Swift 6). User docs: https://docs.hatang.dev/sdk/ios. Distributed from the public mirror https://github.com/sota-labs/hatang-chat-ios (the monorepo's `sdks/ios`).

## Development

```bash
swift test                                                         # core + helpers, on macOS
xcodebuild -scheme HatangChat -destination 'generic/platform=iOS Simulator' build
just conformance ios .conformance/site.json                       # from the repo root, against a running gateway
```

Releases: `just release ios <version>` then push the `ios-v<version>` tag; `.github/workflows/release-swift.yml` pushes a subtree split to the mirror and tags `<version>`.
