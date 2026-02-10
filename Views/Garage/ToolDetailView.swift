import SwiftUI
import Foundation
import SwiftData

/// Detail view for a tool showing full details and usage tracking across jobs.
/// Displays photos, ownership, notes, aliases, and a list of all jobs this tool has been linked to.
struct ToolDetailView: View {
    @Bindable var tool: Tool
    @Environment(\.modelContext) private var viewContext
    @State private var showingEditTool = false
    @State private var showingPurchaseConfirmation = false
    @State private var showingPurchaseSuccess = false
    @State private var showingFullscreenPhoto = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var toolPhotos: [(index: Int, image: UIImage)] = []

    /// Sorted list of job records linked to this tool (most recent first)
    private var linkedJobs: [JobRecord] {
        guard let jobSet = tool.jobRecords else { return [] }
        return jobSet.sorted { $0.jobDate > $1.jobDate }
    }

    /// Number of jobs this tool has been used in
    private var usageCount: Int {
        (tool.jobRecords)?.count ?? 0
    }

    // Design system colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Photo Gallery
                if !toolPhotos.isEmpty {
                    photoGallerySection
                }

                // Tool name & ownership header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.title2)
                            .foregroundColor(steelGray)

                        Text(tool.name)
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

                    // Mark as Purchased button — only for borrowed tools
                    if tool.ownershipType == "borrowed" {
                        Button {
                            showingPurchaseConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cart.badge.checkmark")
                                    .font(.subheadline)
                                Text("Mark as Purchased")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.133, green: 0.773, blue: 0.369))
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                        .accessibilityIdentifier("markAsPurchasedButton")
                    }
                }
                .padding(.horizontal)
                .padding(.top, toolPhotos.isEmpty ? 8 : 0)

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
                if let aliases = tool.aliases, !aliases.isEmpty {
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

                        ForEach(linkedJobs, id: \.id) { job in
                            NavigationLink(destination: JobDetailView(job: job).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(industrialBlue)
                                        .font(.body)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(job.aircraftType.isEmpty ? "Unknown Aircraft" : job.aircraftType)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)

                                        HStack(spacing: 8) {
                                            if !job.system.isEmpty {
                                                Text(job.system)
                                                    .font(.caption)
                                                    .foregroundColor(industrialBlue)
                                            }
                                            Text(job.jobDate, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
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
                HStack {
                    Text("Added to Garage:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(tool.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
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
                .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
        }
        .fullScreenCover(isPresented: $showingFullscreenPhoto) {
            ToolPhotoFullscreenView(
                photos: toolPhotos.map { $0.image },
                selectedIndex: $selectedPhotoIndex
            )
        }
        .alert("Mark as Purchased?", isPresented: $showingPurchaseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Mark as Purchased") {
                ToolService().markAsPurchased(tool)
                showingPurchaseSuccess = true
            }
        } message: {
            Text("'\(tool.name)' will be converted from borrowed to personal. All job records will automatically reflect this change.")
        }
        .alert("Tool Purchased!", isPresented: $showingPurchaseSuccess) {
            Button("OK") { }
        } message: {
            Text("'\(tool.name)' is now a personal tool.")
        }
        .onAppear {
            loadPhotos()
        }
        .onChange(of: showingEditTool) { _, isShowing in
            if !isShowing {
                // Reload photos when edit sheet is dismissed (user may have changed photos)
                loadPhotos()
            }
        }
    }

    // MARK: - Photo Gallery Section

    private var photoGallerySection: some View {
        VStack(spacing: 0) {
            if toolPhotos.count == 1 {
                // Single photo — show full width hero
                singlePhotoView
            } else {
                // Multiple photos — horizontal scroll with hero prominent
                multiPhotoView
            }

            // Photo count indicator
            HStack {
                Spacer()
                Text("\(toolPhotos.count) photo\(toolPhotos.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
                    .padding(.top, 4)
            }
        }
    }

    private var singlePhotoView: some View {
        Button {
            selectedPhotoIndex = 0
            showingFullscreenPhoto = true
        } label: {
            Image(uiImage: toolPhotos[0].image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tool photo, tap to view full screen")
    }

    private var multiPhotoView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(toolPhotos.enumerated()), id: \.element.index) { offset, photo in
                    Button {
                        selectedPhotoIndex = offset
                        showingFullscreenPhoto = true
                    } label: {
                        Image(uiImage: photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: offset == 0 ? 220 : 140,
                                height: 200
                            )
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                // Hero badge on first photo
                                Group {
                                    if offset == 0 {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.white)
                                                    .padding(6)
                                                    .background(industrialBlue.opacity(0.8))
                                                    .clipShape(Circle())
                                                    .padding(6)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(offset + 1) of \(toolPhotos.count)\(offset == 0 ? ", hero photo" : "")")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - Load Photos

    private func loadPhotos() {
        toolPhotos = ToolPhotoService.shared.loadAllPhotos(for: tool)
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return industrialBlue
        case "shop": return steelGray
        case "borrowed": return safetyOrange
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return industrialBlue
        }
    }
}

// MARK: - Fullscreen Photo Viewer

/// Fullscreen photo viewer with swipe navigation between tool photos.
/// Presented as a full screen cover with dismiss gesture.
struct ToolPhotoFullscreenView: View {
    let photos: [UIImage]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                    .accessibilityLabel("Close photo viewer")
                }
                Spacer()

                // Photo counter
                if photos.count > 1 {
                    Text("\(selectedIndex + 1) / \(photos.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 8)
                }
            }
        }
        .statusBarHidden()
    }
}
