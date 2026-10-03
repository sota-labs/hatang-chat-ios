import Foundation

/// Simulator automation without taps (custom-scheme links opened from outside ask for confirmation):
/// write a link such as `hatangexample://send?text=Hi` to `Documents/command.txt` in the app's data
/// container, then post the Darwin notification `dev.hatang.chat.example.command`:
///
/// ```sh
/// dir=$(xcrun simctl get_app_container booted dev.hatang.chat.example data)
/// echo 'hatangexample://open' > "$dir/Documents/command.txt"
/// xcrun simctl spawn booted notifyutil -p dev.hatang.chat.example.command
/// ```
enum Automation {
    static let name = "dev.hatang.chat.example.command"

    @MainActor private static var handler: ((URL) -> Void)?

    @MainActor
    static func listen(_ handle: @escaping (URL) -> Void) {
        handler = handle
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { Automation.run() }
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    @MainActor
    private static func run() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = docs.appendingPathComponent("command.txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: file)
        for line in text.split(whereSeparator: \.isNewline) {
            if let url = URL(string: line.trimmingCharacters(in: .whitespaces)) { handler?(url) }
        }
    }
}
