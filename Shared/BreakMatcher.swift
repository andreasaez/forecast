import Foundation

/// Spots time people block out for themselves (lunch, the gym, walking the dog) so it counts as free time.
///
/// Opt-in only. `CalendarReader` hands over one title at a time and gets back yes or no.
/// The title is not kept, shown, logged or sent anywhere.
enum BreakMatcher {
    /// Words and phrases that mark personal time. Matched as whole words, ignoring case and accents.
    static let breakPhrases = [
        "break", "lunch", "breakfast", "brunch", "dinner", "snack",
        "gym", "workout", "work out", "exercise", "run", "running", "jog",
        "walk", "dog", "dogs", "swim", "yoga", "pilates", "stretch",
        "meditation", "meditate", "mindfulness", "nap", "rest", "recharge",
        "personal", "me time", "school run", "pickup", "pick up", "errand", "errands", "prayer",
    ]

    /// Words that mean it's work after all, as in "Lunch & Learn" or "Walk and call".
    static let workPhrases = [
        "learn", "working", "review", "interview", "sync", "standup", "stand up", "meeting",
        "call", "demo", "workshop", "planning", "retro", "1 1", "one on one", "dry run",
    ]

    static func isBreak(_ title: String?) -> Bool {
        guard let title else { return false }
        let words = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return false }
        let text = " " + words.joined(separator: " ") + " "
        func mentions(_ phrase: String) -> Bool { text.contains(" \(phrase) ") }
        return breakPhrases.contains(where: mentions) && !workPhrases.contains(where: mentions)
    }
}
