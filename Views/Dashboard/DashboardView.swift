import SwiftUI
import CoreData

/// Dashboard view showing recent jobs and quick stats.
struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext

    /// Binding to the selected tab index so the empty state CTA can switch to New Job tab
    @Binding var selectedTab: Int

    /// Fetch recent job records, most recent by job date first
    /// Feature #74: Sort by jobDate for correct date boundary sorting (Dec 31 before Jan 1)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JobRecord.jobDate, ascending: false)],
        animation: .default
    )
    private var jobRecords: FetchedResults<JobRecord>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tool.name, ascending: true)]
    )
    private var tools: FetchedResults<Tool>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // FRO Banner
                    Text("FOR REFERENCE ONLY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.1))
                        .cornerRadius(4)
                        .padding(.top, 8)
                        .accessibilityLabel("For Reference Only disclaimer banner")

                    // Quick Stats
                    HStack(spacing: 16) {
                        StatCard(
                            title: "Jobs Logged",
                            value: "\(jobRecords.count)",
                            icon: "doc.text.fill",
                            color: Color(red: 0.145, green: 0.388, blue: 0.922)
                        )
                        StatCard(
                            title: "Tools",
                            value: "\(tools.count)",
                            icon: "wrench.fill",
                            color: Color(red: 0.392, green: 0.455, blue: 0.545)
                        )
                    }
                    .padding(.horizontal)

                    // Recent Jobs Section or Empty State
                    if jobRecords.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "airplane")
                                .font(.system(size: 60))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("Welcome to FRO")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("For Reference Only")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            Text("Start logging your maintenance jobs\nto build your personal reference library.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            // Large tap target for gloved hands (60pt+ height)
                            Button(action: {
                                selectedTab = 1 // Switch to New Job tab
                            }) {
                                Text("Log Your First Job")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 16)
                                    .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .cornerRadius(12)
                            }
                            .frame(minHeight: 60)
                            .accessibilityLabel("Log Your First Job")
                            .accessibilityHint("Opens the New Job form to create your first maintenance record")
                            .padding(.top, 8)
                        }
                        .padding(.top, 40)
                    } else {
                        // Recent jobs list
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Jobs")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal)

                            ForEach(jobRecords.prefix(10), id: \.objectID) { job in
                                NavigationLink(destination: JobDetailView(job: job)) {
                                    JobCardView(job: job)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AboutView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                            .accessibilityLabel("Settings")
                    }
                }
            }
        }
    }
}

/// Quick stat card for the dashboard
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(title)")
    }
}

/// Simple job card for the dashboard recent jobs list
struct JobCardView: View {
    @ObservedObject var job: JobRecord

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let aircraft = job.aircraftType {
            parts.append(aircraft)
        }
        if let system = job.system, !system.isEmpty {
            parts.append(system)
        }
        if let date = job.jobDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append(formatter.string(from: date))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.aircraftType ?? "Unknown Aircraft")
                    .font(.headline)
                Spacer()
                if let date = job.jobDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let system = job.system, !system.isEmpty {
                Text(system)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            if let desc = job.taskDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Job record: \(accessibilityDescription)")
        .accessibilityHint("Double tap to view job details")
    }
}

#Preview {
    DashboardView(selectedTab: .constant(0))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
