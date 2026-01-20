import Foundation
import SwiftData
import SwiftUI // 为了 AppTheme 的 ColorScheme

// MARK: - 1. 基础设置
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    var id: String { self.rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 2. 数据库模型 (SwiftData)
@Model
class Subject {
    var id: UUID
    var name: String
    var order: Int
    
    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

@Model
class Note {
    var id: UUID
    var tag: String
    var content: String
    var date: Date
    var isFavorite: Bool
    var isPinned: Bool
    var isDeleted: Bool
    
    init(id: UUID = UUID(), tag: String, content: String, date: Date, isFavorite: Bool, isPinned: Bool, isDeleted: Bool = false) {
        self.id = id
        self.tag = tag
        self.content = content
        self.date = date
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isDeleted = isDeleted
    }
}

// MARK: - 3. 备份与传输模型
struct NoteBackup: Codable {
    let id: UUID; let tag: String; let content: String; let date: Date; let isFavorite: Bool; let isPinned: Bool; let isDeleted: Bool
}

struct SubjectBackup: Codable {
    let name: String; let order: Int
}

struct AppDataBackup: Codable {
    let notes: [NoteBackup]
    let subjects: [SubjectBackup]
    var version: String = "1.0"
}

// Supabase 上传专用模型
struct NoteUpload: Codable {
    let id: UUID
    let user_id: UUID
    let tag: String
    let content: String
    let date: Date
    let is_favorite: Bool
    let is_pinned: Bool
    let is_deleted: Bool

    init(from note: Note, userId: UUID) {
        self.id = note.id
        self.user_id = userId
        self.tag = note.tag
        self.content = note.content
        self.date = note.date
        self.is_favorite = note.isFavorite
        self.is_pinned = note.isPinned
        self.is_deleted = note.isDeleted
    }
}
