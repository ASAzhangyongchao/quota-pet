import AppKit

enum ProductInfo {
    static let name = "QuotaPet"
    static let bundleIdentifier = "io.github.asazhangyongchao.quotapet"
}

@main
struct QuotaPetMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
