//
//  ExploreHoldTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Explore holds and waits")
struct ExploreHoldTests {
    @Test("The first show does not wait for a slow Health read past the patience")
    func slowReadDoesNotHold() async {
        let read = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        let clock = ContinuousClock()
        let start = clock.now
        await ExploreArrival.wait(for: read, atMost: .milliseconds(100))
        #expect(clock.now - start < .seconds(2))
        #expect(!read.isCancelled)
        read.cancel()
    }

    @Test("A read that ends first ends the wait at once")
    func quickReadEndsTheWait() async {
        let read = Task<Void, Never> { try? await Task.sleep(for: .milliseconds(20)) }
        let clock = ContinuousClock()
        let start = clock.now
        await ExploreArrival.wait(for: read, atMost: .seconds(5))
        #expect(clock.now - start < .seconds(2))
    }

    @Test("A replan waits while a reader covers the page and while the zoom back lands, then runs once")
    func replanWaitsForTheZoomBack() {
        var hold = ExplorePlanHold()
        func step(_ act: (inout ExplorePlanHold) -> Bool) -> Bool { act(&hold) }
        // First show: nothing held, nothing to wait for.
        #expect(!step { $0.uncover() })
        #expect(step { $0.allowsReplan() })

        // A reader opens: the read and a save are held.
        hold.cover()
        #expect(!step { $0.allowsReplan() })
        #expect(!step { $0.allowsReplan() })

        // Back on Explore: still held while the zoom lands.
        #expect(step { $0.uncover() })
        #expect(!step { $0.allowsReplan() })

        // Landed: the held replan runs once.
        #expect(step { $0.release() })
        #expect(!step { $0.release() })
        #expect(step { $0.allowsReplan() })
    }

    @Test("Nothing held, nothing to replan; covered again before landing keeps holding")
    func releaseOnlyWhatWasHeld() {
        var hold = ExplorePlanHold()
        func step(_ act: (inout ExplorePlanHold) -> Bool) -> Bool { act(&hold) }
        hold.cover()
        #expect(step { $0.uncover() })
        #expect(!step { $0.release() })

        hold.cover()
        #expect(!step { $0.allowsReplan() })
        #expect(step { $0.uncover() })
        hold.cover()
        #expect(!step { $0.release() })
        #expect(step { $0.uncover() })
        #expect(step { $0.release() })
    }
}
