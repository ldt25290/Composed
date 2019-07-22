import Quick
import Nimble
import Foundation

@testable import Composed

final class SectionProviderDelegate_Spec: QuickSpec {

    override func spec() {
        super.spec()

        var global: ComposedSectionProvider!
        var child: Section!
        var delegate: MockDelegate!

        beforeEach {
            global = ComposedSectionProvider()
            delegate = MockDelegate()
            global.updateDelegate = delegate

            child = ArraySection<String>()
            global.append(child)
        }

        it("should call the delegate method for inserting a section") {
            expect(delegate.didInsertSections).toNot(beNil())
        }

        it("should be called from the global provider") {
            expect(delegate.didInsertSections?.provider) === global
        }

        it("should contain only 1 new section") {
            expect(delegate.didInsertSections?.sections.count).to(equal(1))
        }

        it("should be called from child") {
            expect(delegate.didInsertSections?.sections[0]) === child
        }

        it("section should equal 1") {
            expect(delegate.didInsertSections?.indexes) === IndexSet(integer: 0)
        }

    }

}

final class MockDelegate: UpdateDelegate {

    var didInsertSections: (provider: SectionProvider, sections: [Section], indexes: IndexSet)?
    var didInsertElements: (section: Section, index: Int)?

    func provider(_ provider: SectionProvider, didInsertSections sections: [Section], at indexes: IndexSet) {
        didInsertSections = (provider, sections, indexes)
    }

    func section(_ section: Section, didInsertElementAt index: Int) {
        didInsertElements = (section, index)
    }

}
