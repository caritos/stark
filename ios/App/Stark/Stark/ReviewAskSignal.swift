//
//  ReviewAskSignal.swift
//  Stark
//

import Observation

/// Bumped each time a reminder's completion has been written. The main screen watches it and asks
/// `ReviewPromptStore` whether a rating request is due; this type only carries the signal.
@MainActor @Observable
final class ReviewAskSignal {
    private(set) var completions = 0
    func completionLanded() { completions += 1 }
}
