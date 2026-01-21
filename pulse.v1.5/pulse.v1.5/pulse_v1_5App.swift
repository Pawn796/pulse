import SwiftUI
import SwiftData
import Supabase

// 通知定义
extension Notification.Name {
    static let cloudDataChanged = Notification.Name("CloudDataChanged")
    static let cloudDataDeleted = Notification.Name("CloudDataDeleted")
}

// 状态枚举
enum SyncStatus: Equatable {
    case synced
    case syncing
    case error(String)
}

@Observable
class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client = SupabaseClient(supabaseURL: URL(string: "https://hzmynestyvoewvojpevq.supabase.co")!, supabaseKey: "sb_publishable_1won8srlfjkBWk-jvtXyBQ_04McQd3G")
    var currentUser: User? = nil
    var syncStatus: SyncStatus = .synced // 全局同步状态
    
    private var listeningTask: Task<Void, Never>? = nil
    
    init() {
        Task {
            print("🚀 SupabaseManager: 初始化...")
            for await state in client.auth.authStateChanges {
                if state.event == .signedIn || state.event == .initialSession {
                    self.currentUser = state.session?.user
                    if self.currentUser != nil {
                        await subscribeToChanges()
                    }
                } else if state.event == .signedOut {
                    self.currentUser = nil
                    listeningTask?.cancel()
                }
            }
        }
    }
    
    func subscribeToChanges() async {
        listeningTask?.cancel()
        let channel = client.channel("public:notes")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "notes")
        
        do { try await channel.subscribeWithError() }
        catch { print("❌ 订阅失败: \(error)") }
        
        listeningTask = Task {
            for await change in changes {
                switch change {
                case .delete(let action):
                    if let idVal = action.oldRecord["id"],
                       case .string(let idString) = idVal,
                       let uuid = UUID(uuidString: idString) {
                        await MainActor.run {
                            NotificationCenter.default.post(name: .cloudDataDeleted, object: nil, userInfo: ["id": uuid])
                        }
                    }
                default:
                    await MainActor.run {
                        NotificationCenter.default.post(name: .cloudDataChanged, object: nil)
                    }
                }
            }
        }
    }
}

@main
struct PulseApp: App {
    @State private var supabaseManager = SupabaseManager.shared
    
    // ⚠️ 注意：这里不再直接放 @AppStorage，而是交给下面的 PulseRootView 管理
    
    var body: some Scene {
        WindowGroup {
            // 🟢 使用中间视图，确保状态更新能立即响应
            PulseRootView()
                .environment(supabaseManager)
        }
        .modelContainer(for: [Note.self, Subject.self])
    }
}

// 🟢 修改：中间层视图，增加数据初始化逻辑
struct PulseRootView: View {
    @AppStorage("appTheme") private var currentTheme: AppTheme = .system
    @Environment(\.modelContext) private var modelContext // 获取数据库上下文
    
    var body: some View {
        ContentView()
            .preferredColorScheme(currentTheme.colorScheme)
            .animation(.easeInOut(duration: 0.3), value: currentTheme)
            .onAppear {
                initDefaultSubjects()
            }
    }
    
    // 初始化默认科目
    private func initDefaultSubjects() {
        do {
            // 检查是否已有数据
            let descriptor = FetchDescriptor<Subject>()
            let count = try modelContext.fetchCount(descriptor)
            
            if count == 0 {
                print("✨ 检测到科目为空，正在初始化默认科目...")
                let defaults = ["生理", "生化", "病理", "内科", "外科"]
                
                for (index, name) in defaults.enumerated() {
                    let subject = Subject(name: name, order: index)
                    modelContext.insert(subject)
                }
            }
        } catch {
            print("❌ 初始化科目失败: \(error)")
        }
    }
}
