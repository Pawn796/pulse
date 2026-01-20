import SwiftUI
import SwiftData
import Supabase

@Observable
class SupabaseManager {
    static let shared = SupabaseManager()
    // ⚠️ 请替换为你自己的 URL 和 Key
    let client = SupabaseClient(supabaseURL: URL(string: "https://hzmynestyvoewvojpevq.supabase.co")!, supabaseKey: "sb_publishable_1won8srlfjkBWk-jvtXyBQ_04McQd3G")
    var currentUser: User? = nil
    
    init() {
        Task { self.currentUser = try? await client.auth.session.user }
    }
}

@main
struct PulseApp: App {
    @State private var supabaseManager = SupabaseManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(supabaseManager) // 全局注入
        }
        .modelContainer(for: [Note.self, Subject.self])
    }
}
