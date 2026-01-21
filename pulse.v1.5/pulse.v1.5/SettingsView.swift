import SwiftUI
import SwiftData
import Supabase

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    
    @Query private var allNotesForStorage: [Note]
    
    @AppStorage("appTheme") private var currentTheme: AppTheme = .system
    
    @State private var showAuthSheet = false
    @State private var showTrash = false
    @State private var showBackup = false
    @State private var showSignOutAlert = false
    
    @State private var storageSizeString: String = "计算中..."

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. 账号与同步
                Section {
                    HStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(supabaseManager.currentUser != nil ? Color.blue.gradient : Color.gray.gradient)
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: supabaseManager.currentUser != nil ? "person.fill" : "person.crop.circle.badge.questionmark")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let email = supabaseManager.currentUser?.email {
                                Text(email).font(.headline).lineLimit(1)
                                Text("已登录 Supabase 服务器").font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("未登录").font(.headline)
                                Text("登录以同步您的笔记").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if supabaseManager.currentUser != nil { showSignOutAlert = true }
                            else { showAuthSheet = true }
                        }) {
                            Text(supabaseManager.currentUser != nil ? "退出" : "登录")
                                .font(.subheadline).fontWeight(.medium)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground)).cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    
                    if supabaseManager.currentUser != nil {
                        Button(action: performManualSync) {
                            HStack {
                                Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if case .syncing = supabaseManager.syncStatus { ProgressView() }
                                else { Text(syncStatusText).font(.caption).foregroundColor(.secondary) }
                            }
                        }
                    }
                } header: { Text("账号中心") }
                
                // MARK: - 2. 通用设置
                Section("通用设置") {
                                    Picker(selection: themeBinding) {
                                        Text("跟随系统").tag(AppTheme.system)
                                        Text("浅色模式").tag(AppTheme.light)
                                        Text("深色模式").tag(AppTheme.dark)
                                    } label: {
                                        Label("外观主题", systemImage: "paintbrush").foregroundColor(.primary)
                                    }
                                    
                                    // 🟢 新增：科目管理入口
                                    NavigationLink(destination: SubjectManagerView()) {
                                        Label("科目管理", systemImage: "list.bullet.rectangle.portrait")
                                            .foregroundColor(.primary)
                                    }
                                }
                
                // MARK: - 3. 数据管理
                Section("数据管理") {
                    Button(action: { showTrash = true }) {
                        // 🟢 修改：设置颜色为红色，更加醒目
                        Label("废纸篓", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { showBackup = true }) {
                        Label("数据备份与恢复", systemImage: "externaldrive").foregroundColor(.primary)
                    }
                    
                    HStack {
                        Label("存储占用", systemImage: "internaldrive")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(allNotesForStorage.count) 条记忆")
                                .font(.subheadline)
                            Text(storageSizeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - 4. 关于
                Section {
                    HStack {
                        Label("当前版本", systemImage: "info.circle")
                        Spacer()
                        Text("v2.3.0").foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Pulse Note © 2026 \nDesigned for Liuzhou by Gemini with Yeoman")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .center).padding(.top)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onAppear {
                calculateStorageSize()
            }
            .sheet(isPresented: $showAuthSheet) { SupabaseAuthView() }
            .sheet(isPresented: $showTrash) { TrashView() }
            .sheet(isPresented: $showBackup) { DataBackupView() }
        }
    }
    
    // MARK: - 辅助逻辑
    
    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { currentTheme },
            set: { newValue in withAnimation(.easeInOut(duration: 0.3)) { currentTheme = newValue } }
        )
    }
    
    private func calculateStorageSize() {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            self.storageSizeString = "未知"
            return
        }
        
        let databasePath = url.appendingPathComponent("default.store")
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: databasePath.path)
            if let size = attributes[.size] as? Int64 {
                let bcf = ByteCountFormatter()
                bcf.allowedUnits = [.useMB, .useKB]
                bcf.countStyle = .file
                self.storageSizeString = bcf.string(fromByteCount: size)
            }
        } catch {
            self.storageSizeString = "< 1 MB"
        }
    }
    
    private var syncStatusText: String {
        switch supabaseManager.syncStatus {
        case .synced: return "刚刚"
        case .syncing: return "同步中..."
        case .error: return "同步失败"
        }
    }
    
    private func performManualSync() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        Task {
            await SyncService.shared.pushUnsynced(context: modelContext)
            try? await SyncService.shared.pullFromCloud(context: modelContext)
            calculateStorageSize()
        }
    }
}
