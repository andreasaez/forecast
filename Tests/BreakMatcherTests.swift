import Testing

struct BreakMatcherTests {
    @Test(arguments: [
        "Lunch", "BREAK", "Coffee break", "Gym", "Walk the dog", "Dog walk", "Meditation",
        "Yoga 🧘", "Déjeuner break", "School run", "Dinner with family", "Personal time", "Nap",
    ])
    func personalTimeCountsAsABreak(title: String) {
        #expect(BreakMatcher.isBreak(title))
    }

    @Test(arguments: [
        "Lunch & Learn", "Working lunch", "Walk and call with Sam", "Design review", "1:1",
        "Breakout session", "Walkthrough", "Restaurant booking sync", "Dry run", "Quarterly planning", "",
    ])
    func workIsNotABreak(title: String) {
        #expect(!BreakMatcher.isBreak(title))
    }

    @Test func missingTitleIsNotABreak() {
        #expect(!BreakMatcher.isBreak(nil))
    }
}
