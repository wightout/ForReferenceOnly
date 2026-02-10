import SwiftUI
import Foundation
import SwiftData

/// Purchase Justification View - shows borrowed tool history to help justify purchases.
/// Displays borrowed tools sorted by usage frequency, supporting purchase decisions.
struct PurchaseJustificationView: View {
    @Environment(\.modelContext) private var viewContext

    /// Fetch all borrowed tools sorted by name
    @Query(filter: #Predicate<FROTool> { $0.ownershipType == "borrowed" }, sort: \FROTool.name, order: .forward)
    private var borrowedTools: [FROTool]

    // Purchase confirmation state
    @State private var showingPurchaseConfirmation = false
    @State private var toolToPurchase: Tool?
    @State private var showingPurchaseSuccess = false
    @State private var purchasedToolName = ""

    // Design system colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let successGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    /// Borrowed tools sorted by usage count (most used first)
    private var toolsSortedByUsage: [Tool] {
        borrowedTools.sorted { tool1, tool2 in
            let count1 = (tool1.jobRecords)?.count ?? 0
            let count2 = (tool2.jobRecords)?.count ?? 0
            if count1 != count2 {
                return count1 > count2  // Higher usage first
            }
            return tool1.name < tool2.name  // Alphabetical tiebreaker
        }
    }

    /// Get usage count for a tool
    private func usageCount(for tool: Tool) -> Int {
        (tool.jobRecords)?.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // FRO Banner
            HStack {
                Spacer()
                Text("FOR REFERENCE ONLY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(safetyOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(safetyOrange.opacity(0.2))
                    .cornerRadius(4)
                Spacer()
            }
            .padding(.top, 8)

            if borrowedTools.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(steelGray)
                    Text("No Borrowed Tools")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("When you borrow tools and use them in jobs,\nthis view helps you justify purchasing them.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header section with explanation
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "chart.bar.doc.horizontal.fill")
                                    .font(.title2)
                                    .foregroundColor(industrialBlue)
                                Text("Purchase Justification")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            Text("Tools you borrow frequently may be worth purchasing. This view shows your borrowed tools sorted by usage to help justify tool purchases.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        // Summary stats card
                        HStack(spacing: 20) {
                            // Total borrowed tools
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(borrowedTools.count)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(safetyOrange)
                                Text("Borrowed\nTools")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Divider().frame(height: 50)

                            // Total uses across all borrowed tools
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(totalBorrowedUsage)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(industrialBlue)
                                Text("Total Job\nUses")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        .padding(.horizontal)

                        // Borrowed tools list sorted by usage
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(safetyOrange)
                                Text("Frequently Borrowed Tools")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.horizontal)

                            ForEach(toolsSortedByUsage, id: \.id) { tool in
                                NavigationLink(destination: ToolDetailView(tool: tool)) {
                                    PurchaseJustificationRowView(
                                        tool: tool,
                                        usageCount: usageCount(for: tool)
                                    )
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        toolToPurchase = tool
                                        showingPurchaseConfirmation = true
                                    } label: {
                                        Label("Mark as Purchased", systemImage: "cart.badge.checkmark")
                                    }
                                    .tint(successGreen)
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Footer note
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Tip:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            Text("Tools with high usage counts may be good candidates for purchase. Tap any tool to see which jobs it was used in.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(industrialBlue.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Purchase Justification")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Mark as Purchased?", isPresented: $showingPurchaseConfirmation) {
            Button("Cancel", role: .cancel) {
                toolToPurchase = nil
            }
            Button("Mark as Purchased") {
                if let tool = toolToPurchase {
                    let name = tool.name
                    ToolService().markAsPurchased(tool)
                    purchasedToolName = name
                    toolToPurchase = nil
                    showingPurchaseSuccess = true
                }
            }
        } message: {
            Text("'\(toolToPurchase?.name ?? "This tool")' will be converted from borrowed to personal. All job records will automatically reflect this change.")
        }
        .alert("Tool Purchased!", isPresented: $showingPurchaseSuccess) {
            Button("OK") { }
        } message: {
            Text("'\(purchasedToolName)' is now a personal tool. It has been removed from this list.")
        }
    }

    /// Total usage count across all borrowed tools
    private var totalBorrowedUsage: Int {
        borrowedTools.reduce(0) { sum, tool in
            sum + ((tool.jobRecords)?.count ?? 0)
        }
    }
}

// MARK: - Purchase Justification Row View

/// Row view for a borrowed tool showing usage statistics for purchase justification.
struct PurchaseJustificationRowView: View {
    @Bindable var tool: Tool
    let usageCount: Int

    // Design system colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let successGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    /// Justification level based on usage
    private var justificationLevel: (text: String, color: Color) {
        switch usageCount {
        case 0:
            return ("Not used yet", Color.secondary)
        case 1:
            return ("Low usage", Color.secondary)
        case 2...4:
            return ("Moderate usage", safetyOrange)
        case 5...9:
            return ("High usage - consider purchasing", industrialBlue)
        default:
            return ("Very high usage - strongly recommend purchasing", successGreen)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Orange accent bar for borrowed tools
            RoundedRectangle(cornerRadius: 2)
                .fill(safetyOrange)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Tool name
                Text(tool.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                // Borrowed from
                if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(safetyOrange)
                        Text("Borrowed from: \(borrowedFrom)")
                            .font(.caption)
                            .foregroundColor(safetyOrange)
                    }
                }

                // Justification recommendation
                HStack(spacing: 4) {
                    Image(systemName: justificationIcon)
                        .font(.caption2)
                        .foregroundColor(justificationLevel.color)
                    Text(justificationLevel.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(justificationLevel.color)
                }
            }

            Spacer()

            // Usage count badge (prominent)
            VStack(spacing: 2) {
                Text("\(usageCount)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(industrialBlue)
                Text("uses")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 50)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var justificationIcon: String {
        switch usageCount {
        case 0:
            return "minus.circle"
        case 1:
            return "arrow.up.circle"
        case 2...4:
            return "arrow.up.circle.fill"
        case 5...9:
            return "checkmark.circle"
        default:
            return "checkmark.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        PurchaseJustificationView()
            
    }
}
