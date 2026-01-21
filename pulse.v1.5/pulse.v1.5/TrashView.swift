import SwiftUI
import SwiftData
import Supabase

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    @Environment(\.dismiss) var dismiss // 🟢 可选：如果你想添加关闭按钮，可以用这个
    
    @Query(filter: #Predicate<Note> { $0.isDeleted == true }, sort: \Note.date, order: .reverse)
    private var deletedNotes: [Note]
    
    @State private var showClearAllAlert = false
    @State private var noteToDeletePermanently: Note? = nil

    var body: some View {
        // 🟢 核心修复：必须用 NavigationStack 包裹，否则弹窗里不显示标题栏和工具栏
        NavigationStack {
            Group {
                if deletedNotes.isEmpty {
                    ContentUnavailableView("废纸篓为空", systemImage: "trash", description: Text("删除的笔记会暂时存放在这里"))
                } else {
                    List {
                        ForEach(deletedNotes) { note in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(note.content)
                                    .font(.system(size: 16))
                                    .lineLimit(2)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    if !note.tag.isEmpty {
                                        Text(note.tag)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(4)
                                    }
                                    Spacer()
                                    Text("已删除")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .leading) {
                                Button {
                                    withAnimation {
                                        restoreNote(note)
                                    }
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    noteToDeletePermanently = note
                                } label: {
                                    Label("彻底删除", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    // 🟢 工具栏：放在 List 上，并指定位置
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) {
                                showClearAllAlert = true
                            } label: {
                                Text("清空全部")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("废纸篓")
            .navigationBarTitleDisplayMode(.inline)
            // 彻底删除确认
            .confirmationDialog("彻底删除笔记？", isPresented: Binding(get: { noteToDeletePermanently != nil }, set: { if !$0 { noteToDeletePermanently = nil } }), titleVisibility: .visible) {
                Button("彻底删除", role: .destructive) {
                    if let n = noteToDeletePermanently {
                        deletePermanently(n)
                    }
                }
                Button("取消", role: .cancel) { noteToDeletePermanently = nil }
            } message: {
                Text("该操作不可撤销。")
            }
            // 清空确认
            .confirmationDialog("确定清空废纸篓？", isPresented: $showClearAllAlert, titleVisibility: .visible) {
                Button("清空所有", role: .destructive) {
                    clearAll()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("废纸篓内的所有记录将被永久删除。")
            }
        }
    }
    
    // MARK: - 逻辑方法
    
    private func restoreNote(_ note: Note) {
        note.isDeleted = false
        note.lastModified = Date()
        note.needsSync = true
        Task { try? await syncNoteToCloud(note) }
    }
    
    private func deletePermanently(_ note: Note) {
        let noteId = note.id
        // 先删除云端
        Task {
            try? await supabaseManager.client.from("notes").delete().eq("id", value: noteId).execute()
        }
        // 再删除本地
        modelContext.delete(note)
        noteToDeletePermanently = nil
    }
    
    private func clearAll() {
        let ids = deletedNotes.map { $0.id }
        // 批量删除云端
        Task {
            try? await supabaseManager.client.from("notes").delete().in("id", values: ids).execute()
        }
        // 批量删除本地
        for note in deletedNotes {
            modelContext.delete(note)
        }
    }
    
    private func syncNoteToCloud(_ note: Note) async throws {
        guard let userId = supabaseManager.currentUser?.id else { return }
        let upload = NoteUpload(from: note, userId: userId)
        try await supabaseManager.client.from("notes").upsert(upload).execute()
        await MainActor.run {
            note.needsSync = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSyncTime")
        }
    }
}
