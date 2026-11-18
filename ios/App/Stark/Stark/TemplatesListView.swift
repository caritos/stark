//
//  TemplatesListView.swift
//  Stark
//
//  The templates for the current kind: tap one to fill the Add form, swipe to delete.
//

import SwiftUI
import StarkKit

struct TemplatesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TemplatesModel.self) private var model
    let kind: TemplateKind
    let onPick: (ItemTemplate) -> Void

    var body: some View {
        let items = model.templates(for: kind)
        List {
            ForEach(items) { template in
                Button {
                    onPick(template)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).foregroundStyle(Colors.text)
                        if template.title != template.name {
                            Text(template.title).font(.footnote).foregroundStyle(Colors.textSecondary)
                        }
                    }
                }
                .accessibilityHint("Fills the form. Swipe left to delete.")
            }
            .onDelete { offsets in
                for i in offsets { model.delete(items[i].id) }
            }
            if items.isEmpty {
                Text("No templates yet.").foregroundStyle(Colors.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
