import SwiftUI
import SwiftData
import Supabase
import UniformTypeIdentifiers

struct DataBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    
    @Query private var allNotes: [Note]
    @Query private var allSubjects: [Subject]
    
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDocument: JSONDocument?
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isSyncing = false
    
    var body: some View {
        List {
            Section(header: Text("云端同步 (Supabase)")) {
                Button(action: syncToCloud) {
                    HStack {
                        Label("立即同步到云端", systemImage: "icloud.and.arrow.up")
                        if isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSyncing || supabaseManager.currentUser == nil)
                
                Button(action: { Task { await fetchFromCloud() } }) {
                    Label("从云端恢复数据", systemImage: "icloud.and.arrow.down")
                }
                .disabled(isSyncing || supabaseManager.currentUser == nil)
            }
            
            Section(header: Text("本地文件备份")) {
                Button(action: prepareExport) {
                    Label("备份数据到文件", systemImage: "square.and.arrow.up")
                }
                Button(action: { showImporter = true }) {
                    Label("从文件恢复数据", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("备份与恢复")
        .alert("提示", isPresented: $showAlert) {
            Button("好") {}
        } message: {
            Text(alertMessage)
        }
        .fileExporter(isPresented: $showExporter, document: backupDocument, contentType: .json, defaultFilename: "Pulse_Backup.json") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if let url = try? result.get() {
                restoreData(from: url)
            }
        }
    }
    
    // MARK: - 逻辑方法
    
    private func syncToCloud() {
        guard let userId = supabaseManager.currentUser?.id else { return }
        isSyncing = true
        Task {
            do {
                let uploads = allNotes.map { NoteUpload(from: $0, userId: userId) }
                try await supabaseManager.client.from("notes").upsert(uploads).execute()
                alertMessage = "同步完成"
                await MainActor.run {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSyncTime")
                }
            } catch {
                alertMessage = "同步失败: \(error.localizedDescription)"
            }
            isSyncing = false
            showAlert = true
        }
    }
    
    private func fetchFromCloud() async {
        guard let userId = supabaseManager.currentUser?.id else { return }
        isSyncing = true
        do {
            let cloudNotes: [NoteUpload] = try await supabaseManager.client.from("notes").select().eq("user_id", value: userId).execute().value
            for c in cloudNotes {
                if let localNote = allNotes.first(where: { $0.id == c.id }) {
                    if c.last_modified > localNote.lastModified {
                        localNote.content = c.content
                        localNote.tag = c.tag
                        localNote.isPinned = c.is_pinned
                        localNote.isFavorite = c.is_favorite
                        localNote.isDeleted = c.is_deleted
                        localNote.lastModified = c.last_modified
                        localNote.needsSync = false
                    }
                } else {
                    let newNote = Note(id: c.id, tag: c.tag, content: c.content, date: c.date, isFavorite: c.is_favorite, isPinned: c.is_pinned, isDeleted: c.is_deleted)
                    newNote.needsSync = false
                    modelContext.insert(newNote)
                }
            }
            alertMessage = "恢复完成"
            await MainActor.run {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSyncTime")
            }
        } catch {
            alertMessage = "恢复失败: \(error.localizedDescription)"
        }
        isSyncing = false
        showAlert = true
    }
    
    private func prepareExport() {
        let fullBackup = AppDataBackup(
            notes: allNotes.map { NoteBackup(id: $0.id, tag: $0.tag, content: $0.content, date: $0.date, isFavorite: $0.isFavorite, isPinned: $0.isPinned, isDeleted: $0.isDeleted) },
            subjects: allSubjects.map { SubjectBackup(name: $0.name, order: $0.order) }
        )
        if let data = try? JSONEncoder().encode(fullBackup) {
            backupDocument = JSONDocument(message: String(data: data, encoding: .utf8) ?? "")
            showExporter = true
        }
    }
    
    private func restoreData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if let data = try? Data(contentsOf: url),
           let backup = try? JSONDecoder().decode(AppDataBackup.self, from: data) {
            let existingIDs = Set(allNotes.map { $0.id })
            for n in backup.notes where !existingIDs.contains(n.id) {
                modelContext.insert(Note(id: n.id, tag: n.tag, content: n.content, date: n.date, isFavorite: n.isFavorite, isPinned: n.isPinned, isDeleted: n.isDeleted))
            }
            alertMessage = "恢复成功"
            showAlert = true
        }
    }
}
