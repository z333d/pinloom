import AppKit
import Darwin

/// Nonactivating panels receive mouse events, but their owning application
/// cannot normally change the system cursor while another app is active.
/// This optional WindowServer connection property allows it without taking
/// focus. It is private API: resolve it at runtime and keep the visible resize
/// handle as a fallback if a future macOS version removes this capability.
@MainActor
enum BackgroundCursor {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private typealias CopyProperty = @convention(c) (Int32, Int32, CFString, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> Int32

    private static let symbols = UnsafeMutableRawPointer(bitPattern: -2)

    @discardableResult
    static func enable() -> Bool {
        guard let connection = connection(),
              let symbol = dlsym(symbols, "CGSSetConnectionProperty") else { return false }
        let setter = unsafeBitCast(symbol, to: SetProperty.self)
        return setter(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
            && isEnabled
    }

    static var isEnabled: Bool {
        guard let connection = connection(),
              let symbol = dlsym(symbols, "CGSCopyConnectionProperty") else { return false }
        let getter = unsafeBitCast(symbol, to: CopyProperty.self)
        var value: Unmanaged<CFTypeRef>?
        guard getter(connection, connection, "SetsCursorInBackground" as CFString, &value) == 0,
              let property = value?.takeRetainedValue() else { return false }
        return CFEqual(property, kCFBooleanTrue)
    }

    private static func connection() -> Int32? {
        guard let symbol = dlsym(symbols, "CGSMainConnectionID") ?? dlsym(symbols, "_CGSDefaultConnection") else { return nil }
        let connection = unsafeBitCast(symbol, to: Connection.self)()
        return connection > 0 ? connection : nil
    }
}
