
import XCTest
import RealityKit
@testable import Movie_Theater_Experience

@MainActor
class ImmersiveSpaceManagerTests: XCTestCase {

    var immersiveSpaceManager: ImmersiveSpaceManager!
    var mockDelegate: MockImmersiveSpaceDelegate!

    override func setUp() {
        super.setUp()
        immersiveSpaceManager = ImmersiveSpaceManager.shared
        mockDelegate = MockImmersiveSpaceDelegate()
        immersiveSpaceManager.addDelegate(mockDelegate)
        immersiveSpaceManager.configure(
            dismissImmersiveSpace: { },
            dismissWindow: { _ in },
            openWindow: { _ in },
            openImmersiveSpace: { return true }
        )
    }

    override func tearDown() {
        immersiveSpaceManager.removeDelegate(mockDelegate)
        immersiveSpaceManager = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testSingleton() {
        let instance1 = ImmersiveSpaceManager.shared
        let instance2 = ImmersiveSpaceManager.shared
        XCTAssertTrue(instance1 === instance2)
    }

    func testPrepareForOpening() async {
        let result = await immersiveSpaceManager.prepareForOpening()
        XCTAssertTrue(result)
        XCTAssertEqual(immersiveSpaceManager.state, .transitioning(.opening))
        XCTAssertTrue(mockDelegate.willOpenCalled)
    }

    func testHandleOpenSuccess() {
        immersiveSpaceManager.handleOpenSuccess()
        XCTAssertEqual(immersiveSpaceManager.state, .open)
        XCTAssertTrue(mockDelegate.didOpenCalled)
    }

    func testHandleOpenFailure() {
        immersiveSpaceManager.handleOpenFailure()
        XCTAssertEqual(immersiveSpaceManager.state, .closed)
        XCTAssertTrue(mockDelegate.didFailToOpenCalled)
    }

    func testInitiateCleanup() async {
        // To test cleanup, we first need to be in the .open state
        immersiveSpaceManager.handleOpenSuccess()
        await immersiveSpaceManager.initiateCleanup()
        XCTAssertEqual(immersiveSpaceManager.state, .closed)
        XCTAssertTrue(mockDelegate.didCloseCalled)
    }

    func testAddAndRemoveDelegate() {
        let newDelegate = MockImmersiveSpaceDelegate()
        immersiveSpaceManager.addDelegate(newDelegate)
        // We can't directly check the delegates array, but we can infer from behavior
        immersiveSpaceManager.removeDelegate(newDelegate)
    }
}

class MockImmersiveSpaceDelegate: ImmersiveSpaceDelegate {
    var willOpenCalled = false
    var didOpenCalled = false
    var didFailToOpenCalled = false
    var didCloseCalled = false

    func immersiveSpaceWillOpen() {
        willOpenCalled = true
    }

    func immersiveSpaceDidOpen() {
        didOpenCalled = true
    }

    func immersiveSpaceDidFailToOpen() {
        didFailToOpenCalled = true
    }

    func immersiveSpaceDidClose() {
        didCloseCalled = true
    }
}
