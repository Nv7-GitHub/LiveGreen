import Testing
@testable import GreenCore

@Suite("Results text: material names and personal details")
struct ResultsTextTests {
    @Test func materialKeysReadAsPlainNames() {
        #expect(MaterialNames.displayName("pet") == "PET plastic")
        #expect(MaterialNames.displayName("poly_coated_paperboard") == "plastic-lined paperboard")
        #expect(MaterialNames.displayName("carbon_fibre") == "carbon fibre")
        let glasses = [MaterialShare(material: "glass", percent: 10), MaterialShare(material: "steel", percent: 70),
                       MaterialShare(material: "other_plastic", percent: 20)]
        #expect(MaterialNames.summary(glasses, category: .household) == "70% steel, 20% other plastic, 10% glass")
    }

    @Test func foodIsNeverCalledOrganic() {
        // "100% food organic" read as an organic claim (05, 12, 13, 22).
        #expect(MaterialNames.summary([MaterialShare(material: "food_organic", percent: 100)], category: .food) == nil)
        let pints = [MaterialShare(material: "food_organic", percent: 85),
                     MaterialShare(material: "poly_coated_paperboard", percent: 14), MaterialShare(material: "pp", percent: 1)]
        #expect(MaterialNames.summary(pints, category: .food) == "Packed in plastic-lined paperboard, polypropylene")
        // Outside food the key is spelled out rather than hidden, so a mis-tagged spray stays visible.
        let spray = [MaterialShare(material: "food_organic", percent: 85), MaterialShare(material: "hdpe", percent: 12)]
        #expect(MaterialNames.summary(spray, category: .household) == "85% food or plant matter, 12% HDPE plastic")
    }

    @Test func aNotebookStickersDetailsAreFound() {
        let lines = ["CHEM NOTEBOOK", "Name: Alex Rivera", "123 Main St", "Boston, MA 02115", "(617) 555-0123",
                     "CHEMISTRY 101", "100 sheets"]
        #expect(PersonalText.sensitiveLines(lines) == [1, 2, 3, 4])
    }

    @Test func labelsNamesAndEmailsAreFound() {
        #expect(PersonalText.sensitiveLines(["NAME", "Jordan Lee", "Period 3"]) == [0, 1])
        #expect(PersonalText.sensitiveLines(["Jordan Lee", "42 Elm Street"]) == [0, 1])
        #expect(PersonalText.sensitiveLines(["jordan.lee@example.com"]) == [0])
    }

    @Test func productLabelsAreLeftAlone() {
        let lines = ["Nerds Gummy Clusters", "NET WT 5 OZ (141.7g)", "5449000000996", "Model A2337", "65W USB-C",
                     "Rated 100-240V 50/60Hz", "Keep frozen"]
        #expect(PersonalText.sensitiveLines(lines).isEmpty)
    }
}
