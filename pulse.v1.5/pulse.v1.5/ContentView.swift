import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    
    // 数据查询
    @Query(filter: #Predicate<Note> { $0.isDeleted == false }, sort: \Note.date, order: .reverse)
    private var allNotes: [Note]
    
    @Query(sort: \Subject.order) private var subjects: [Subject]
    
    // 状态
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isFavSelected = false
    @State private var selectedSubject: String? = nil
    @State private var showFilterPanel = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    
    @State private var showSettings = false
    @State private var showAddNote = false
    @State private var noteToEdit: Note? = nil

    // 筛选逻辑
    var filteredNotes: [Note] {
        let filtered = allNotes.filter { note in
            let favMatch = isFavSelected ? note.isFavorite : true
            let subjectMatch = (selectedSubject == nil || note.tag == selectedSubject)
            let searchMatch = searchText.isEmpty || note.content.localizedCaseInsensitiveContains(searchText)
            
            var dateMatch = true
            let calendar = Calendar.current
            
            if let start = startDate {
                let startLimit = calendar.startOfDay(for: start)
                dateMatch = dateMatch && (note.date >= startLimit)
            }
            
            if let end = endDate {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: end) {
                    let endLimit = calendar.startOfDay(for: nextDay)
                    dateMatch = dateMatch && (note.date < endLimit)
                }
            }
            
            return favMatch && subjectMatch && searchMatch && dateMatch
        }
        return filtered.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.date > $1.date
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. 标题栏
                HomeHeaderView(
                    showSettings: $showSettings,
                    showAddNote: $showAddNote,
                    onStatusTap: {
                        Task { try? await SyncService.shared.pullFromCloud(context: modelContext) }
                    }
                )
                
                // 2. 搜索与筛选控制栏
                VStack(spacing: 12) {
                    SearchBarView(
                        searchText: $searchText,
                        showDateFilter: $showFilterPanel,
                        isFocused: $isSearchFocused
                    )
                    
                    if showFilterPanel {
                        filterPanelView
                    }
                }
                .padding(.bottom, 10)

                // 3. 列表区域
                if filteredNotes.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            NoteRowView(note: note, highlightText: searchText)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button { noteToEdit = note } label: { Label("编辑", systemImage: "pencil") }
                                    Button { togglePinned(note) } label: { Label(note.isPinned ? "取消置顶" : "置顶记录", systemImage: note.isPinned ? "pin.slash" : "pin") }
                                    Button { toggleFavorite(note) } label: { Label(note.isFavorite ? "取消收藏" : "收藏", systemImage: note.isFavorite ? "star.slash" : "star") }
                                    Divider()
                                    // 🟢 修复点1：长按菜单删除逻辑
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // 🟢 修复点2：侧滑菜单删除逻辑
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: { Label("删除", systemImage: "trash") }
                                    
                                    Button { toggleFavorite(note) } label: { Label(note.isFavorite ? "取消" : "收藏", systemImage: note.isFavorite ? "star.slash" : "star") }.tint(.orange)
                                    Button { togglePinned(note) } label: { Label(note.isPinned ? "取消" : "置顶", systemImage: note.isPinned ? "pin.slash" : "pin") }.tint(.blue)
                                    Button { noteToEdit = note } label: { Label("编辑", systemImage: "pencil") }.tint(.gray)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .sheet(item: $noteToEdit) { note in
                NoteEditorView(subjects: subjects, note: note)
            }
            .sheet(isPresented: $showAddNote) {
                NoteEditorView(subjects: subjects, note: nil)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // 监听云端物理删除通知（彻底删除）
            .onReceive(NotificationCenter.default.publisher(for: .cloudDataDeleted)) { notification in
                guard let id = notification.userInfo?["id"] as? UUID else { return }
                let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
                if let notes = try? modelContext.fetch(descriptor), let noteToDelete = notes.first {
                    modelContext.delete(noteToDelete)
                }
            }
            // 监听云端数据变更（修改、软删除、新增）
            .onReceive(NotificationCenter.default.publisher(for: .cloudDataChanged)) { _ in
                Task {
                    try? await SyncService.shared.pullFromCloud(context: modelContext)
                }
            }
        }
    }

    // 🟢 核心修复：统一的删除处理方法
    private func deleteNote(_ note: Note) {
        withAnimation {
            note.isDeleted = true
            note.lastModified = Date() // ⚠️ 关键：必须更新时间戳，否则手机端会认为这是旧数据而忽略
            note.needsSync = true
            Task { await SyncService.shared.syncNote(note) }
        }
    }

    // 辅助方法：切换置顶
    private func togglePinned(_ note: Note) {
        withAnimation(.spring()) {
            note.isPinned.toggle()
            note.lastModified = Date()
            note.needsSync = true
            Task { await SyncService.shared.syncNote(note) }
        }
    }

    // 辅助方法：切换收藏
    private func toggleFavorite(_ note: Note) {
        withAnimation(.spring()) {
            note.isFavorite.toggle()
            note.lastModified = Date()
            note.needsSync = true
            Task { await SyncService.shared.syncNote(note) }
        }
    }

    // 筛选面板
    private var filterPanelView: some View {
        VStack(spacing: 12) {
            CustomDatePickerRow(title: "起始时间", date: $startDate) { isSearchFocused = false }
            Divider()
            CustomDatePickerRow(title: "结束时间", date: $endDate) { isSearchFocused = false }
            
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("科目与标记")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                
                FilterBarView(
                    subjects: subjects,
                    isFavSelected: $isFavSelected,
                    selectedSubject: $selectedSubject,
                    onFilterTap: { isSearchFocused = false }
                )
            }
            
            if startDate != nil || endDate != nil {
                Divider()
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation {
                        startDate = nil
                        endDate = nil
                    }
                }) {
                    Text("重置时间筛选")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyStateView: some View {
        ContentUnavailableView("无记忆", systemImage: "note.text")
    }
}
