import AppKit
import CoreServices
import XCTest
@testable import Pinloom

final class LaunchPresentationTests: XCTestCase {
    func testOpeningAppShowsTheLineWithOrWithoutAnAppleEvent() {
        XCTAssertTrue(LaunchPresentation.shouldShowLine(for: nil))
        XCTAssertTrue(LaunchPresentation.shouldShowLine(for: openApplicationEvent()))
    }

    func testLoginLaunchStaysHidden() {
        let event = openApplicationEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                       forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(LaunchPresentation.shouldShowLine(for: event))
    }

    private func openApplicationEvent() -> NSAppleEventDescriptor {
        let eventClass = AEEventClass(kCoreEventClass)
        let eventID = AEEventID(kAEOpenApplication)
        let returnID = AEReturnID(kAutoGenerateReturnID)
        let transactionID = AETransactionID(kAnyTransactionID)
        return NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                     targetDescriptor: nil, returnID: returnID,
                                     transactionID: transactionID)
    }
}
