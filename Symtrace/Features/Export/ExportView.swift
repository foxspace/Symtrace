// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// Doctor-ready export: PDF report + CSV. Phase 4.
struct ExportView: View {
    var body: some View {
        ContentUnavailableView(
            "Export coming soon",
            systemImage: "square.and.arrow.up",
            description: Text("PDF and CSV export will let you share a clear symptom timeline with your doctor.")
        )
        .navigationTitle("Export")
    }
}
