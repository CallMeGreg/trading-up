import SwiftUI

/// The one-time explainer shown after the 2.0 reset (and reachable again from
/// Settings), plus the fallback notice for a quarantined save. Copy comes from
/// `ChaseLoadIssue` so the model owns the message.
struct WhatsNewView: View {
    @Environment(ChaseState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let issue: ChaseLoadIssue

    var body: some View {
        ZStack {
            Palette.screen.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: icon)
                        .font(.system(size: 52))
                        .foregroundStyle(Color(hex: "ffd54a"))
                        .padding(.top, 40)

                    Text(issue.heading)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)

                    Text(issue.body)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel(18)

                    BigButton(title: "Start Hunting", systemImage: "figure.run",
                              tint: [Palette.money, Color(hex: "39c46e")]) {
                        state.dismissLoadIssue()
                        dismiss()
                    }
                }
                .padding(20)
                .readableWidth()
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var icon: String {
        switch issue {
        case .resetForNewVersion: return "sparkles"
        case .unreadable:         return "exclamationmark.triangle.fill"
        case .fromNewerVersion:   return "arrow.up.circle.fill"
        }
    }
}
