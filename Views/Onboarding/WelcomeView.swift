import SwiftUI

/// Welcome/onboarding screen shown on first app launch.
/// Explains the app's purpose and displays the "For Reference Only" disclaimer.
struct WelcomeView: View {
    /// Callback when the user dismisses the welcome screen.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // App icon / hero
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 72))
                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                        .padding(.bottom, 8)

                    // App name
                    Text("For Reference Only")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231)) // Dark charcoal

                    Text("FRO")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray

                    // Purpose explanation
                    VStack(spacing: 16) {
                        Text("Your Personal Maintenance Reference Tool")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text("FRO helps aircraft mechanics capture and organize practical maintenance knowledge — the tools, consumables, chemicals, workarounds, and notes that official systems don't preserve.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        // Feature highlights
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureRow(
                                icon: "doc.text.fill",
                                title: "Log Jobs",
                                description: "Record what you actually used and did"
                            )
                            FeatureRow(
                                icon: "wrench.fill",
                                title: "Build Your Garage",
                                description: "Track your personal tool inventory"
                            )
                            FeatureRow(
                                icon: "mic.fill",
                                title: "Voice Capture",
                                description: "Brain-dump after a task, hands-free"
                            )
                            FeatureRow(
                                icon: "magnifyingglass",
                                title: "Search & Find",
                                description: "Quickly find past jobs and what you used"
                            )
                            FeatureRow(
                                icon: "doc.richtext",
                                title: "Share as PDF",
                                description: "Generate reference reports for your team"
                            )
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 20)
                }
            }

            // Disclaimer + Continue button at bottom
            VStack(spacing: 16) {
                // Prominent FRO Disclaimer
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                        Text("FOR REFERENCE ONLY")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                    }
                    Text("This app is not authoritative maintenance data. It is a personal reference tool to help you prepare for repeat tasks. Always follow official technical manuals and procedures.")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.1))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.6), lineWidth: 1.5)
                )

                // Continue button
                Button(action: onContinue) {
                    Text("I Understand — Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                        .cornerRadius(12)
                }
                .accessibilityIdentifier("welcomeContinueButton")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 12)
            .background(Color(.systemBackground))
        }
        .background(Color(red: 0.973, green: 0.980, blue: 0.988)) // Light gray #F8FAFC
        .edgesIgnoringSafeArea(.bottom)
    }
}

/// A row showing a feature highlight with icon, title, and description.
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
