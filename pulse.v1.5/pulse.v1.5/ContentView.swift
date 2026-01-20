import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Supabase

// MARK: - 主视图
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    
    // 逻辑修复：直接在 Query 级别过滤掉 isDeleted 的笔记，确保主界面列表即时刷新
    @Query(filter: #Predicate<Note> { $0.isDeleted == false }, sort: \Note.date, order: .reverse)
    private var allNotes: [Note]
    
    @Query(sort: \Subject.order) private var subjects: [Subject]
    
    @AppStorage("appTheme") private var currentTheme: AppTheme = .system
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    @State private var isFavSelected = false
    @State private var selectedSubject: String? = nil
    @State private var showDateFilter = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    
    @State private var noteToEdit: Note? = nil
    @State private var showAddNote = false
    @State private var showSettings = false
    
    let defaultSubjects = ["生理", "生化", "病理", "内科", "外科"]
    
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
                if let endLimit = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) {
                    dateMatch = dateMatch && (note.date <= endLimit)
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
                headerView
                searchBarArea
                filterBar

                if filteredNotes.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            NoteRowView(note: note, highlightText: searchText)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    // 逻辑改进：左滑仅保留删除、置顶、收藏
                                    Button(role: .destructive) { moveToTrash(note) } label: { Label("删除", systemImage: "trash") }
                                    Button { togglePin(note) } label: { Label(note.isPinned ? "取消置顶" : "置顶", systemImage: note.isPinned ? "pin.slash" : "pin.fill") }.tint(.blue)
                                    Button { toggleFavorite(note) } label: { Label(note.isFavorite ? "取消收藏" : "收藏", systemImage: note.isFavorite ? "star.slash" : "star") }.tint(.orange)
                                }
                                .contextMenu {
                                    // 逻辑改进：长按保留编辑
                                    Button(action: { noteToEdit = note }) { Label("编辑", systemImage: "pencil") }
                                    Button(action: { togglePin(note) }) { Label(note.isPinned ? "取消置顶" : "置顶", systemImage: note.isPinned ? "pin.slash" : "pin.fill") }
                                    Button(action: { toggleFavorite(note) }) { Label(note.isFavorite ? "取消收藏" : "收藏", systemImage: note.isFavorite ? "star.slash" : "star") }
                                    Divider()
                                    Button(role: .destructive, action: { moveToTrash(note) }) { Label("放入废纸篓", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $noteToEdit) { note in NoteEditorView(subjects: subjects, note: note) }
            .sheet(isPresented: $showAddNote) { NoteEditorView(subjects: subjects, note: nil) }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .preferredColorScheme(currentTheme.colorScheme)
        .onAppear {
            if subjects.isEmpty {
                for (index, name) in defaultSubjects.enumerated() {
                    modelContext.insert(Subject(name: name, order: index))
                }
            }
        }
    }

    private func moveToTrash(_ note: Note) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            note.isDeleted = true
        }
    }
    
    private func toggleFavorite(_ note: Note) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.bouncy(duration: 0.4)) { note.isFavorite.toggle() }
    }
    
    private func togglePin(_ note: Note) {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        withAnimation(.bouncy(duration: 0.4)) { note.isPinned.toggle() }
    }
}

// MARK: - 恢复原始 UI 组件
extension ContentView {
    private var headerView: some View {
        HStack(alignment: .bottom) {
            Text("记忆库").font(.system(size: 34, weight: .bold))
            Spacer()
            HStack(spacing: 20) {
                Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
                Button(action: { isSearchFocused = false; showAddNote = true }) { Image(systemName: "plus") }
            }
            .font(.system(size: 20, weight: .medium)).foregroundColor(.primary)
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 15)
    }

    private var searchBarArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("搜索内容...", text: $searchText)
                        .focused($isSearchFocused)
                        .submitLabel(.done)
                    if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) } }
                }
                .padding(10).background(Color(.secondarySystemBackground)).cornerRadius(12)
                
                Button(action: { isSearchFocused = false; withAnimation(.spring()) { showDateFilter.toggle() } }) {
                    Image(systemName: showDateFilter ? "calendar.badge.minus" : "calendar.badge.clock")
                        .font(.system(size: 18)).foregroundColor(showDateFilter ? .orange : .blue)
                        .padding(10).background(Color(.secondarySystemBackground)).cornerRadius(12)
                }
            }.padding(.horizontal)
            if showDateFilter { dateFilterView }
        }
    }

    private var itemWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - 32 - 40) / 6
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(title: "收藏", isSelected: isFavSelected) {
                    isSearchFocused = false
                    withAnimation(.spring()) { isFavSelected.toggle() }
                }
                .frame(width: itemWidth)
                
                ForEach(subjects) { subject in
                    filterButton(title: subject.name, isSelected: selectedSubject == subject.name) {
                        isSearchFocused = false
                        withAnimation(.spring()) { selectedSubject = (selectedSubject == subject.name) ? nil : subject.name }
                    }
                    .frame(width: itemWidth)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    @ViewBuilder
    func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if title == "收藏" { Image(systemName: isSelected ? "star.fill" : "star").font(.system(size: 16)) }
                else { Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Color.yellow : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? .black : .primary)
            .cornerRadius(10)
        }
    }

    private var dateFilterView: some View {
        VStack(spacing: 15) {
            VStack(spacing: 12) {
                CustomDatePickerRow(title: "起始时间", date: $startDate) { isSearchFocused = false }
                CustomDatePickerRow(title: "结束时间", date: $endDate) { isSearchFocused = false }
            }
            Button(action: { withAnimation { startDate = nil; endDate = nil } }) {
                Text("重置筛选").font(.system(size: 14, weight: .medium)).foregroundColor(.red).frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.red.opacity(0.1)).cornerRadius(8)
            }
        }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "没有笔记" : "无搜索结果",
                  systemImage: searchText.isEmpty ? "note.text" : "magnifyingglass")
        } description: {
            Text(searchText.isEmpty ? "点击右上角 + 号添加你的第一条笔记" : "换个关键词试试看？")
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - 设置、科目、备份页面保持原有 UI
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appTheme") private var currentTheme: AppTheme = .system
    @Environment(SupabaseManager.self) var supabaseManager
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("同步账号")) {
                    if let user = supabaseManager.currentUser {
                        HStack {
                            Image(systemName: "person.fill.checkmark").foregroundColor(.green)
                            Text(user.email ?? "已登录用户").lineLimit(1)
                        }
                        Button("退出登录", role: .destructive) {
                            Task { try? await supabaseManager.client.auth.signOut(); supabaseManager.currentUser = nil }
                        }
                    } else {
                        NavigationLink(destination: SupabaseAuthView()) { Label("登录 Supabase 开启同步", systemImage: "icloud") }
                    }
                }
                Section(header: Text("外观")) {
                    Picker("主题风格", selection: $currentTheme) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.rawValue).tag(theme) }
                    }.pickerStyle(.menu)
                }
                Section(header: Text("内容管理")) {
                    NavigationLink(destination: SubjectManagerView()) { Label("科目管理", systemImage: "tag") }
                    NavigationLink(destination: TrashView()) { Label("废纸篓", systemImage: "trash").foregroundColor(.red) }
                    NavigationLink(destination: DataBackupView()) { Label("备份与恢复", systemImage: "externaldrive") }
                }
                Section(header: Text("关于")) {
                    HStack { Text("版本"); Spacer(); Text("v2.1.0").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct SubjectManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.order) private var subjects: [Subject]
    @State private var newSubjectName = ""
    var body: some View {
        List {
            Section(header: Text("添加新科目")) {
                HStack {
                    TextField("输入科目名称", text: $newSubjectName)
                    Button(action: addNewSubject) { Image(systemName: "plus.circle.fill").font(.title2) }.disabled(newSubjectName.isEmpty)
                }
            }
            Section(header: Text("已有科目")) {
                ForEach(subjects) { subject in Text(subject.name) }
                .onDelete(perform: deleteSubject)
                .onMove(perform: moveSubject)
            }
        }
        .navigationTitle("科目管理")
        .toolbar { EditButton() }
    }
    private func addNewSubject() {
        modelContext.insert(Subject(name: newSubjectName, order: subjects.count))
        newSubjectName = ""
    }
    private func deleteSubject(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(subjects[index]) }
    }
    private func moveSubject(from source: IndexSet, to destination: Int) {
        var items = subjects
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() { item.order = index }
    }
}

// MARK: - 废纸篓恢复确认逻辑
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Note> { $0.isDeleted == true }, sort: \Note.date, order: .reverse) private var deletedNotes: [Note]
    
    @State private var showClearAllAlert = false
    @State private var noteToDeletePermanently: Note? = nil

    var body: some View {
        Group {
            if deletedNotes.isEmpty {
                ContentUnavailableView("废纸篓为空", systemImage: "trash", description: Text("删除的笔记会暂时存放在这里"))
            } else {
                List {
                    ForEach(deletedNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.content).font(.system(size: 16)).lineLimit(2).strikethrough().foregroundColor(.secondary)
                            HStack {
                                if !note.tag.isEmpty {
                                    Text(note.tag).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Color(.systemGray5)).cornerRadius(4)
                                }
                                Spacer()
                                Text("已删除").font(.caption).foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading) {
                            Button { withAnimation { note.isDeleted = false } } label: { Label("恢复", systemImage: "arrow.uturn.backward") }.tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { noteToDeletePermanently = note } label: { Label("彻底删除", systemImage: "trash.fill") }
                        }
                    }
                }
                .toolbar { ToolbarItem(placement: .destructiveAction) { Button("清空") { showClearAllAlert = true } } }
            }
        }
        .navigationTitle("废纸篓")
        .confirmationDialog("彻底删除笔记？", isPresented: Binding(get: { noteToDeletePermanently != nil }, set: { if !$0 { noteToDeletePermanently = nil } }), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) { if let n = noteToDeletePermanently { modelContext.delete(n); noteToDeletePermanently = nil } }
            Button("取消", role: .cancel) { noteToDeletePermanently = nil }
        } message: { Text("该操作不可撤销。") }
        .confirmationDialog("确定清空废纸篓？", isPresented: $showClearAllAlert, titleVisibility: .visible) {
            Button("清空所有", role: .destructive) { for note in deletedNotes { modelContext.delete(note) } }
            Button("取消", role: .cancel) { }
        } message: { Text("废纸篓内的所有记录将被永久删除。") }
    }
}

// MARK: - 恢复原始编辑器 UI
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    let subjects: [Subject]; let note: Note?
    
    @State private var content: String = ""
    @State private var selectedTag: String = ""
    @State private var isPinned: Bool = false
    @State private var isFavorite: Bool = false
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("笔记内容").font(.headline).foregroundColor(.secondary)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $content).frame(minHeight: 200).padding(8).scrollContentBackground(.hidden).background(Color(.secondarySystemBackground)).cornerRadius(12).focused($isEditorFocused)
                                if content.isEmpty { Text("开始输入内容...").foregroundColor(.gray.opacity(0.6)).padding(.top, 16).padding(.leading, 14).allowsHitTesting(false) }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("所属科目 (点击可取消)").font(.headline).foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(subjects) { subject in
                                        Button(action: {
                                            selectedTag = (selectedTag == subject.name) ? "" : subject.name
                                            isEditorFocused = false
                                        }) {
                                            Text(subject.name).font(.system(size: 14, weight: .medium))
                                                .padding(.horizontal, 12).frame(height: 40)
                                                .background(selectedTag == subject.name ? Color.yellow : Color(.secondarySystemBackground))
                                                .foregroundColor(selectedTag == subject.name ? .black : .primary).cornerRadius(10)
                                        }
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 15) {
                            Text("标记选项").font(.headline).foregroundColor(.secondary)
                            HStack(spacing: 15) {
                                toggleOption(title: "置顶", isOn: $isPinned, icon: "pin.fill", color: .blue)
                                toggleOption(title: "收藏", isOn: $isFavorite, icon: "star.fill", color: .orange)
                            }
                        }
                    }.padding(16).frame(minHeight: geometry.size.height)
                }.scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(note == nil ? "新增记录" : "编辑笔记").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let n = note { n.content = content; n.tag = selectedTag; n.isPinned = isPinned; n.isFavorite = isFavorite; n.isDeleted = false }
                        else { modelContext.insert(Note(tag: selectedTag, content: content, date: Date(), isFavorite: isFavorite, isPinned: isPinned)) }
                        dismiss()
                    }.bold().disabled(content.isEmpty)
                }
            }
            .onAppear {
                if let n = note { content = n.content; selectedTag = n.tag; isPinned = n.isPinned; isFavorite = n.isFavorite }
            }
        }
    }
    
    @ViewBuilder private func toggleOption(title: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Button(action: { isOn.wrappedValue.toggle(); isEditorFocused = false }) {
            HStack { Image(systemName: icon).foregroundColor(isOn.wrappedValue ? color : .gray); Text(title).font(.system(size: 15, weight: .medium)); Spacer(); Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle").foregroundColor(isOn.wrappedValue ? .green : .gray.opacity(0.3)) }.padding().frame(maxWidth: .infinity).background(Color(.secondarySystemBackground)).cornerRadius(12)
        }.foregroundColor(.primary)
    }
}

// MARK: - 恢复原始卡片 UI (带高亮)
struct NoteRowView: View {
    let note: Note; let highlightText: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if !note.tag.isEmpty {
                    Text(note.tag).font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(.systemGray5)).cornerRadius(6).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if note.isPinned { Image(systemName: "pin.fill").foregroundColor(.blue).font(.system(size: 14)) }
                    if note.isFavorite { Image(systemName: "star.fill").foregroundColor(.yellow).font(.system(size: 16)) }
                }
            }
            highlightedText(content: note.content, query: highlightText).font(.system(size: 17)).lineSpacing(5).foregroundColor(.primary)
            HStack { Spacer(); Text(note.date, format: .dateTime.day().month().year().hour().minute()).font(.system(size: 12)).foregroundColor(.secondary) }
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
    
    private func highlightedText(content: String, query: String) -> Text {
        guard !query.isEmpty, content.localizedCaseInsensitiveContains(query) else { return Text(content) }
        let parts = content.components(separatedBy: query); var result = Text("")
        for (index, part) in parts.enumerated() {
            result = result + Text(part); if index < parts.count - 1 { result = result + Text(query).foregroundColor(.orange).bold() }
        }
        return result
    }
}

// MARK: - 备份恢复及其他逻辑组件恢复
struct DataBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) var supabaseManager
    @Query private var allNotes: [Note]; @Query private var allSubjects: [Subject]
    @State private var showExporter = false; @State private var showImporter = false
    @State private var backupDocument: JSONDocument?; @State private var alertMessage = ""; @State private var showAlert = false; @State private var isSyncing = false
    var body: some View {
        List {
            Section(header: Text("云端同步 (Supabase)")) {
                Button(action: syncToCloud) { HStack { Label("立即同步到云端", systemImage: "icloud.and.arrow.up"); if isSyncing { Spacer(); ProgressView() } } }.disabled(isSyncing || supabaseManager.currentUser == nil)
                Button(action: fetchFromCloud) { Label("从云端恢复数据", systemImage: "icloud.and.arrow.down") }.disabled(isSyncing || supabaseManager.currentUser == nil)
            }
            Section(header: Text("本地文件备份")) {
                Button(action: prepareExport) { Label("备份数据到文件", systemImage: "square.and.arrow.up") }
                Button(action: { showImporter = true }) { Label("从文件恢复数据", systemImage: "square.and.arrow.down") }
            }
        }
        .navigationTitle("备份与恢复").alert("提示", isPresented: $showAlert) { Button("好") {} } message: { Text(alertMessage) }
        .fileExporter(isPresented: $showExporter, document: backupDocument, contentType: .json, defaultFilename: "Pulse_Backup.json") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in if let url = try? result.get() { restoreData(from: url) } }
    }
    private func syncToCloud() {
        guard let userId = supabaseManager.currentUser?.id else { return }; isSyncing = true
        Task { do { let uploads = allNotes.map { NoteUpload(from: $0, userId: userId) }; try await supabaseManager.client.from("notes").upsert(uploads).execute(); alertMessage = "同步完成"; showAlert = true } catch { alertMessage = error.localizedDescription; showAlert = true }; isSyncing = false }
    }
    private func fetchFromCloud() {
        guard let userId = supabaseManager.currentUser?.id else { return }; isSyncing = true
        Task { do { let cloudNotes: [NoteUpload] = try await supabaseManager.client.from("notes").select().eq("user_id", value: userId).execute().value; let localIDs = Set(allNotes.map { $0.id }); for c in cloudNotes where !localIDs.contains(c.id) { modelContext.insert(Note(id: c.id, tag: c.tag, content: c.content, date: c.date, isFavorite: c.is_favorite, isPinned: c.is_pinned, isDeleted: c.is_deleted)) }; alertMessage = "恢复完成"; showAlert = true } catch { alertMessage = error.localizedDescription; showAlert = true }; isSyncing = false }
    }
    private func prepareExport() {
        let fullBackup = AppDataBackup(notes: allNotes.map { NoteBackup(id: $0.id, tag: $0.tag, content: $0.content, date: $0.date, isFavorite: $0.isFavorite, isPinned: $0.isPinned, isDeleted: $0.isDeleted) }, subjects: allSubjects.map { SubjectBackup(name: $0.name, order: $0.order) })
        if let data = try? JSONEncoder().encode(fullBackup) { backupDocument = JSONDocument(message: String(data: data, encoding: .utf8) ?? ""); showExporter = true }
    }
    private func restoreData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(AppDataBackup.self, from: data) { let existingIDs = Set(allNotes.map { $0.id }); for n in backup.notes where !existingIDs.contains(n.id) { modelContext.insert(Note(id: n.id, tag: n.tag, content: n.content, date: n.date, isFavorite: n.isFavorite, isPinned: n.isPinned, isDeleted: n.isDeleted)) }; alertMessage = "恢复成功"; showAlert = true }
    }
}

struct CustomDatePickerRow: View {
    let title: String; @Binding var date: Date?; var onInteraction: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.subheadline).foregroundColor(.primary); Spacer()
            ZStack {
                if let selectedDate = date { Text(selectedDate, format: .dateTime.year().month().day()).foregroundColor(.primary).padding(.horizontal, 12).padding(.vertical, 6).background(Color.blue.opacity(0.1)).cornerRadius(8) }
                else { Text("选择日期").foregroundColor(.gray.opacity(0.6)).padding(.horizontal, 12).padding(.vertical, 6).background(Color.gray.opacity(0.1)).cornerRadius(8) }
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = $0; onInteraction() }), displayedComponents: .date).labelsHidden().blendMode(.destinationOver)
            }
        }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var message: String
    init(message: String) { self.message = message }
    init(configuration: ReadConfiguration) throws { message = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: message.data(using: .utf8)!)
    }
}

#Preview { ContentView().modelContainer(for: [Note.self, Subject.self], inMemory: true) }
