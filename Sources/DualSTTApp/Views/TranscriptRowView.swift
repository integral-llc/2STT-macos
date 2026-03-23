import SwiftUI
import DualSTT

struct TranscriptRowView: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            sourceTag
            timestamp
            transcriptText
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var sourceTag: some View {
        Text(entry.source.rawValue)
            .font(.caption.monospaced().bold())
            .foregroundStyle(tagColor)
            .frame(width: 45, alignment: .center)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tagColor.opacity(0.12))
            )
    }

    private var timestamp: some View {
        Text(entry.timestamp, format: .dateTime.hour().minute().second())
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
    }

    private var transcriptText: some View {
        Text(entry.text)
            .font(.body)
            .opacity(entry.isFinal ? 1.0 : 0.6)
            .italic(!entry.isFinal)
    }

    private var tagColor: Color {
        entry.source == .me ? .blue : .green
    }
}
