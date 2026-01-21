import SwiftUI
import SwiftData
import Supabase

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    let subjects: [Subject]
    let note: Note?
    
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
                        // 内容输入区
                        VStack(alignment: .leading, spacing: 10) {
                            Text("笔记内容").font(.headline).foregroundColor(.secondary)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $content)
                                    .frame(minHeight: 200)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .focused($isEditorFocused)
                                
                                if content.isEmpty {
                                    Text("开始输入内容...")
                                        .foregroundColor(.gray.opacity(0.6))
                                        .padding(.top, 16)
                                        .padding(.leading, 14)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        
                        // 科目选择区
                        VStack(alignment: .leading, spacing: 12) {
                            Text("所属科目").font(.headline).foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(subjects) { subject in
                                        Button(action: {
                                            selectedTag = (selectedTag == subject.name) ? "" : subject.name
                                            isEditorFocused = false
                                        }) {
                                            Text(subject.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .padding(.horizontal, 12)
                                                .frame(height: 40)
                                                .background(selectedTag == subject.name ? Color.yellow : Color(.secondarySystemBackground))
                                                .foregroundColor(selectedTag == subject.name ? .black : .primary)
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 标记选项
                        HStack(spacing: 15) {
                            toggleButton(title: "置顶", isOn: $isPinned, icon: "pin.fill", color: .blue)
                            toggleButton(title: "收藏", isOn: $isFavorite, icon: "star.fill", color: .orange)
                        }
                    }
                    .padding(16)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(note == nil ? "新增记录" : "编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveNote() }
                        .bold().disabled(content.isEmpty)
                }
            }
            .onAppear {
                if let n = note {
                    content = n.content
                    selectedTag = n.tag
                    isPinned = n.isPinned
                    isFavorite = n.isFavorite
                } else {
                    // 自动弹出键盘
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isEditorFocused = true
                    }
                }
            }
        }
    }
    
    private func saveNote() {
        let finalNote: Note
        if let n = note {
            n.content = content
            n.tag = selectedTag
            n.isPinned = isPinned
            n.isFavorite = isFavorite
            n.isDeleted = false
            n.lastModified = Date()
            n.needsSync = true
            finalNote = n
        } else {
            finalNote = Note(tag: selectedTag, content: content, date: Date(), isFavorite: isFavorite, isPinned: isPinned)
            modelContext.insert(finalNote)
        }
        
        // 使用 SyncService 同步
        Task { await SyncService.shared.syncNote(finalNote) }
        dismiss()
    }
    
    @ViewBuilder
    private func toggleButton(title: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            isEditorFocused = false
        } label: {
            HStack {
                Image(systemName: icon).foregroundColor(isOn.wrappedValue ? color : .gray)
                Text(title)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn.wrappedValue ? .green : .gray.opacity(0.3))
            }
            .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
        }
        .foregroundColor(.primary)
    }
}
