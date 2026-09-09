import Testing

@testable import ZenithData

@Suite("Position")
struct PositionTests {
    @Test("atEnd with no existing rows returns the gap")
    func atEndEmpty() {
        #expect(Position.atEnd(nil) == 1000)
    }

    @Test("atEnd appends a full gap after the max")
    func atEndAppends() {
        #expect(Position.atEnd(1000) == 2000)
        #expect(Position.atEnd(2500) == 3500)
    }

    @Test("between with no neighbors returns the gap")
    func betweenEmpty() {
        #expect(Position.between(nil, nil) == 1000)
    }

    @Test("between at the start subtracts a half-gap from after")
    func betweenAtStart() {
        #expect(Position.between(nil, 1000) == 500)
    }

    @Test("between at the end adds a full gap to before")
    func betweenAtEnd() {
        #expect(Position.between(1000, nil) == 2000)
    }

    @Test("between two neighbors is the midpoint")
    func betweenMidpoint() {
        #expect(Position.between(1000, 2000) == 1500)
        #expect(Position.between(1000, 1010) == 1005)
    }
}
