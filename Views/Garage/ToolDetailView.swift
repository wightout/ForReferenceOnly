import SwiftUI
import CoreData

/// Detail view for a tool showing full details and usage tracking across jobs.
/// Displays ownership, notes, aliases, and a list of all jobs this tool has been linked to.
struct ToolDetailView: View {
    @ObservedObject var tool: Tool
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingEditTool = false

    /// Sorted list of job records linked to this tool (most recent first)
    private var linkedJobs: [JobRecord] {
        guard let jobSet = tool.jobRecords as? Set<JobRecord> else { return [] }
        return jobSet.sorted { ($0.jobDate ?? Date.distantPast) > ($1.jobDate ?? Date.distantPast) }
    }

    /// Number of jobs this tool has been used in
    private var usageCount: Int {
        (tool.jobRecords as? Set<JobRecord>)?.count ?? 0
    }

    // Design system colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Tool name & ownership header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.title2)
                            .foregroundColor(steelGray)

                        Text(tool.name ?? "Unnamed Tool")
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()
                    }

                    // Ownership badge
                    HStack(spacing: 8) {
                        Text(ownershipLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(ownershipColor.opacity(0.15))
                            .foregroundColor(ownershipColor)
                            .clipShape(Capsule())

                        if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(safetyOrange)
                                Text("from \(borrowedFrom)")
                                    .font(.subheadline)
                                    .foregroundColor(safetyOrange)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Notes
                if let notes = tool.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(notes)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                // Aliases
                if let aliases = tool.aliases as? [String], !aliases.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Also Known As")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(aliases.joined(separator: ", "))
                            .font(.body)
                            .italic()
                    }
                    .padding(.horizontal)
                }

                Divider().padding(.horizontal)

                // Usage tracking section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(industrialBlue)
                        Text("Usage Tracking")
                            .font(.headline)
                        Spacer()
                    }

                    // Usage count card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(usageCount)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(industrialBlue)
                            Text("job\(usageCount == 1 ? "" : "s") using this tool")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(industrialBlue.opacity(0.08))
                    .cornerRadius(12)

                    // List of jobs
                    if linkedJobs.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Not used in any jobs yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    } else {
                        Text("Jobs Using This Tool")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        ForEach(linkedJobs, id: \.objectID) { job in
                            NavigationLink(destination: JobDetailView(job: job).environment(\.managedObjectContext, viewContext)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(industrialBlue)
                                        .font(.body)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(job.aircraftType ?? "Unknown Aircraft")
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)

                                        HStack(spacing: 8) {
                                            if let system = job.system, !system.isEmpty {
                                                Text(system)
                                                    .font(.caption)
                                                    .foregroundColor(industrialBlue)
                                            }
                                            if let date = job.jobDate {
                                                Text(date, style: .date)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        if let component = job.component, !component.isEmpty {
                                            Text(component)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Created date
                if let created = tool.createdAt {
                    HStack {
                        Text("Added to Garage:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(created, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Tool Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingEditTool = true }) {
                    Text("Edit")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Edit Tool")
            }
        }
        .sheet(isPresented: $showingEditTool) {
            EditToolView(tool: tool)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return industrialBlue
        case "shop": return steelGray
        case "borrowed": return safetyOrange
        default: return industrialBlue
        }
    }
}
