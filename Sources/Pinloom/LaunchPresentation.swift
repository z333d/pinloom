import AppKit
import CoreServices

enum LaunchPresentation {
    /// Login launches stay unobtrusive; opening the app is an explicit request
    /// to see the board, including when there are no saved cards yet.
    static func shouldShowLine(for event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return true }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            != OSType(keyAELaunchedAsLogInItem)
    }
}
