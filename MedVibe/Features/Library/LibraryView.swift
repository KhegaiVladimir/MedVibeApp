import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \MedicalRecord.date, order: .reverse)
    private var records: [MedicalRecord]

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.title)
                            .font(.headline)

                        Text(record.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(record.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Library")
        }
    }
}
