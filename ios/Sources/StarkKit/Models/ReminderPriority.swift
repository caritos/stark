// ios/Sources/StarkKit/Models/ReminderPriority.swift

/// The three priority levels the UI offers (plus none), mapped like Apple Reminders onto the
/// iCal `PRIORITY` value stored in the `.ics`: low 9, medium 5, high 1 (1 is the highest in iCal).
public enum ReminderPriority: Int, CaseIterable, Equatable, Sendable {
    case none, low, medium, high

    /// The value written to `PRIORITY`; nil means no line is written.
    public var icalValue: Int? {
        switch self {
        case .none: return nil
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    /// Maps any stored iCal value to the nearest level: 1-4 high, 5 medium, 6-9 low, else none.
    public init(icalValue: Int?) {
        guard let value = icalValue else { self = .none; return }
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    /// "", "!", "!!" or "!!!" — what the agenda row shows before the title.
    public var marks: String {
        String(repeating: "!", count: rawValue)
    }

    /// The segmented picker's label.
    public var pickerLabel: String {
        self == .none ? "None" : marks
    }

    /// The value to store after the user edits: the original is kept untouched while the chosen
    /// level still matches it (an imported `PRIORITY:3` stays 3), otherwise the chosen level's
    /// value is written.
    public static func updated(original: Int?, chosen: ReminderPriority) -> Int? {
        ReminderPriority(icalValue: original) == chosen ? original : chosen.icalValue
    }
}
