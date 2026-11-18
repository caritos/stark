//
//  TemplatesModel.swift
//  Stark
//
//  The saved item templates (in UserDefaults on this device only). All rules (names, limits,
//  what a template holds, applying) are StarkKit `ItemTemplates`; this holds the persistence.
//

import Foundation
import Observation
import UIKit
import StarkKit

@MainActor @Observable
final class TemplatesModel {
    static let key = "templates.v1"

    private(set) var templates: ItemTemplates

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var unreadable: Data?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Reading never writes. A blob this build cannot read (newer version or corrupt) is copied
        // to a backup key before the first save overwrites it.
        let stored = defaults.data(forKey: Self.key)
        unreadable = ItemTemplates.isUnreadable(stored) ? stored : nil
        templates = ItemTemplates.decode(stored)
    }

    func templates(for kind: TemplateKind) -> [ItemTemplate] {
        templates.templates(for: kind)
    }

    /// Returns a plain message when the template was refused, nil when saved.
    func add(name: String, from snapshot: TemplateSnapshot) -> String? {
        var next = templates
        do {
            try next.add(name: name, from: snapshot)
        } catch let error as TemplateError {
            UIAccessibility.post(notification: .announcement, argument: error.message)
            return error.message
        } catch {
            return TemplateError.notFound.message
        }
        templates = next
        persist()
        return nil
    }

    func delete(_ id: UUID) {
        templates.delete(id)
        persist()
    }

    private func persist() {
        if let unreadable {
            if defaults.data(forKey: Self.key + ".unreadable") == nil {
                defaults.set(unreadable, forKey: Self.key + ".unreadable")
            }
            self.unreadable = nil
        }
        defaults.set(templates.encoded(), forKey: Self.key)
    }
}

extension ItemKind {
    var templateKind: TemplateKind { self == .event ? .event : .reminder }
}
