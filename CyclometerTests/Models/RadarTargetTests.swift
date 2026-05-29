import Testing
@testable import Cyclometer

@Suite("RadarTarget")
struct RadarTargetTests {

    @Test("Each target has a unique identity")
    func uniqueIDs() {
        let t1 = RadarTarget(id: UUID(), relativeVelocityMPS: 15, rangeMetres: 80, threatLevel: .warning)
        let t2 = RadarTarget(id: UUID(), relativeVelocityMPS: 15, rangeMetres: 80, threatLevel: .warning)
        #expect(t1.id != t2.id)
    }

    @Test("Threat levels are equatable")
    func threatEquality() {
        let t = RadarTarget(id: UUID(), relativeVelocityMPS: 20, rangeMetres: 30, threatLevel: .danger)
        #expect(t.threatLevel == .danger)
        #expect(t.threatLevel != .warning)
    }

    @Test("RadarTarget conforms to Equatable")
    func equatable() {
        let id = UUID()
        let t1 = RadarTarget(id: id, relativeVelocityMPS: 10, rangeMetres: 50, threatLevel: .allClear)
        let t2 = RadarTarget(id: id, relativeVelocityMPS: 10, rangeMetres: 50, threatLevel: .allClear)
        #expect(t1 == t2)
    }
}
