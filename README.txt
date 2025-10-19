Somewhere Clean Starter (SwiftUI, iOS 17)

Clean reset steps:
1) In Xcode, create a fresh iOS App project named 'Somewhere' (SwiftUI, Swift).
2) In the new project, DELETE these auto-created files if they exist:
   - ContentView.swift
   - <ProjectName>App.swift (the default @main)
3) Drag the contents of this folder into Xcode. Ensure 'Copy items if needed' is checked
   and the 'Somewhere' target is selected for all files.
4) Build and Run on iOS 17+ simulator.

What's included:
- SomewhereApp.swift         (single @main entry point)
- Models.swift               (data models with explicit Hashable/Equatable)
- DropStore.swift            (simple in-memory store + sample data)
- RootTabView.swift          (tab shell)
- HomeView.swift             (CTA to create a drop)
- MapScreen.swift            (MapKit with pins and create button)
- DropCreationScreen.swift   (form to create a drop)
- DropDetailScreen.swift     (sheet for reactions/lift)
- DropsListScreen.swift      (list of drops)
- FriendsScreen.swift        (placeholder)
- SettingsScreen.swift       (placeholder with toggles)
