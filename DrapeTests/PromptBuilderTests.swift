import XCTest
@testable import Drape

final class PromptBuilderTests: XCTestCase {

    func test_build_includesRoomAndProductFraming() {
        let prompt = PromptBuilder.build(placement: .sofaThrow)
        XCTAssertTrue(prompt.contains("IMAGE 1 is the ROOM"))
        XCTAssertTrue(prompt.contains("IMAGE 2 is the PRODUCT"))
    }

    func test_build_usesPresetInstructionForPlacement() {
        let prompt = PromptBuilder.build(placement: .sofaThrow)
        XCTAssertTrue(prompt.contains(Placement.sofaThrow.instruction))
    }

    func test_build_custom_usesTrimmedCustomInstruction() {
        let prompt = PromptBuilder.build(
            placement: .custom,
            customInstruction: "  draped over the wooden chair on the right  "
        )
        XCTAssertTrue(prompt.contains("draped over the wooden chair on the right"))
        // No leading/trailing whitespace leaked into the TASK line.
        XCTAssertFalse(prompt.contains("IMAGE 1,   draped"))
    }

    func test_build_appendsExtraNotesWhenPresent() {
        let prompt = PromptBuilder.build(
            placement: .rug,
            extraNotes: "làm phòng sáng hơn một chút"
        )
        XCTAssertTrue(prompt.contains("ADDITIONAL REQUEST FROM THE USER: làm phòng sáng hơn một chút"))
    }

    func test_build_omitsExtraNotesSectionWhenBlank() {
        let prompt = PromptBuilder.build(placement: .rug, extraNotes: "   ")
        XCTAssertFalse(prompt.contains("ADDITIONAL REQUEST FROM THE USER"))
    }

    func test_allPlacementsHaveVietnameseLabels() {
        for placement in Placement.allCases {
            XCTAssertFalse(placement.label.isEmpty, "\(placement) missing label")
        }
    }
}
