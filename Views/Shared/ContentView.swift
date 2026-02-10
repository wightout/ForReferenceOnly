import SwiftUI

/// Main content view with tab-based navigation.
/// Provides the 4 main tabs: Dashboard, New Job, Garage, Search.
struct ContentView: View {
    @Environment(\.modelContext) private var viewContext

    /// Selected tab index. Supports launch argument "-startTab" for testing.
    @State private var selectedTab: Int

    init() {
        // Check for launch argument to start on a specific tab (for testing)
        // Priority: command-line args > environment variables > default
        let args = ProcessInfo.processInfo.arguments
        var tabFromArgs: Int?
        if let tabArgIndex = args.firstIndex(of: "-startTab"), tabArgIndex + 1 < args.count,
           let tabIndex = Int(args[tabArgIndex + 1]), (0...3).contains(tabIndex) {
            tabFromArgs = tabIndex
        }

        if let tab = tabFromArgs {
            _selectedTab = State(initialValue: tab)
        } else if let idx = ProcessInfo.processInfo.environment["START_TAB"],
           let tabIndex = Int(idx), (0...3).contains(tabIndex) {
            _selectedTab = State(initialValue: tabIndex)
        } else {
            _selectedTab = State(initialValue: 0)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(0)
                .accessibilityLabel("Dashboard")
                .accessibilityHint("View recent jobs and quick stats")

            NewJobView(selectedTab: $selectedTab)
                .tabItem {
                    Label("New Job", systemImage: "plus.circle.fill")
                }
                .tag(1)
                .accessibilityLabel("New Job")
                .accessibilityHint("Create a new job record")

            GarageView()
                .tabItem {
                    Label("Garage", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(2)
                .accessibilityLabel("Garage")
                .accessibilityHint("Manage your tools, consumables, and chemicals")

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(3)
                .accessibilityLabel("Search")
                .accessibilityHint("Search your job records")
        }
        .tint(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue #2563EB
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}
