import Foundation
import GreenCore

/// A chip the user picked in the questions sheet.
nonisolated struct QuestionAnswer: Hashable, Sendable {
    let question: PendingQuestion
    let option: AnswerOption
}
