import SwiftUI
import SwiftData
import Supabase

// 单例服务，专门处理同步逻辑
class SyncService {
    static let shared = SyncService()
    private let manager = SupabaseManager.shared
    
    // 获取当前用户ID的辅助属性
    private var userId: UUID? { manager.currentUser?.id }

    // MARK: - 核心：增量同步 (拉取)
    @MainActor
    func pullFromCloud(context: ModelContext) async throws {
        guard let uid = userId else { return }
        
        manager.syncStatus = .syncing
        
        do {
            // 1. 准备时间戳
            let lastSyncTime = UserDefaults.standard.double(forKey: "lastSyncTime")
            let lastSyncDate = Date(timeIntervalSince1970: lastSyncTime)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoDate = formatter.string(from: lastSyncDate)
            
            // 2. 增量查询
            let cloudNotes: [NoteUpload] = try await manager.client
                .from("notes")
                .select()
                .eq("user_id", value: uid)
                .gt("last_modified", value: isoDate)
                .execute()
                .value
            
            if !cloudNotes.isEmpty {
                print("☁️ SyncService: 拉取到 \(cloudNotes.count) 条更新")
                
                // MARK: - 性能优化部分开始
                // 3. 仅查询云端变更了 ID 对应的本地笔记，避免全量加载
                let cloudIds = cloudNotes.map { $0.id }
                
                // 使用 Predicate 过滤出涉及变更的本地笔记
                // 注意：SwiftData 支持在 Predicate 中使用外部数组的 contains
                let descriptor = FetchDescriptor<Note>(
                    predicate: #Predicate<Note> { note in
                        cloudIds.contains(note.id)
                    }
                )
                let localNotes = try context.fetch(descriptor)
                
                // 将本地笔记转为字典 [UUID: Note]，将查找复杂度从 O(N) 降为 O(1)
                let localNotesMap = Dictionary(uniqueKeysWithValues: localNotes.map { ($0.id, $0) })
                
                for c in cloudNotes {
                    if let localNote = localNotesMap[c.id] {
                        // 冲突解决：以云端为准（或者比较时间）
                        if c.last_modified > localNote.lastModified {
                            localNote.update(from: c)
                        }
                    } else {
                        // 本地没有，直接插入新笔记
                        let newNote = Note(from: c)
                        context.insert(newNote)
                    }
                }
                // MARK: - 性能优化部分结束
                
            } else {
                print("☁️ SyncService: 云端无新数据")
            }
            
            // 4. 完成
            updateLastSyncTime()
            manager.syncStatus = .synced
            
        } catch {
            print("❌ SyncService 拉取失败: \(error)")
            manager.syncStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - 推送所有未同步数据
    @MainActor
    func pushUnsynced(context: ModelContext) async {
        guard let uid = userId else { return }
        
        // 查找需要同步的笔记
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.needsSync })
        guard let unsyncedNotes = try? context.fetch(descriptor), !unsyncedNotes.isEmpty else { return }
        
        manager.syncStatus = .syncing
        
        let uploads = unsyncedNotes.map { NoteUpload(from: $0, userId: uid) }
        
        do {
            try await manager.client.from("notes").upsert(uploads).execute()
            
            // 更新本地状态
            for note in unsyncedNotes { note.needsSync = false }
            updateLastSyncTime()
            manager.syncStatus = .synced
            print("☁️ SyncService: 成功推送 \(uploads.count) 条数据")
        } catch {
            print("❌ SyncService 推送失败: \(error)")
            manager.syncStatus = .error(error.localizedDescription)
        }
    }
    
    // MARK: - 单条操作
    @MainActor
    func syncNote(_ note: Note) async {
        guard let uid = userId else { return }
        manager.syncStatus = .syncing
        
        do {
            let upload = NoteUpload(from: note, userId: uid)
            try await manager.client.from("notes").upsert(upload).execute()
            
            note.needsSync = false
            updateLastSyncTime()
            manager.syncStatus = .synced
        } catch {
            manager.syncStatus = .error(error.localizedDescription)
        }
    }
    
    // 辅助：更新同步时间
    private func updateLastSyncTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSyncTime")
    }
}

// 扩展 Note 以便 SyncService 使用
extension Note {
    convenience init(from upload: NoteUpload) {
        self.init(id: upload.id, tag: upload.tag, content: upload.content, date: upload.date, isFavorite: upload.is_favorite, isPinned: upload.is_pinned, isDeleted: upload.is_deleted)
        self.needsSync = false
    }
    
    func update(from upload: NoteUpload) {
        self.content = upload.content
        self.tag = upload.tag
        self.isPinned = upload.is_pinned
        self.isFavorite = upload.is_favorite
        self.isDeleted = upload.is_deleted
        self.lastModified = upload.last_modified
        self.needsSync = false
    }
}
