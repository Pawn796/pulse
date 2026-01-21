import SwiftUI
import SwiftData

struct SubjectManagerView: View {
    @Environment(\.modelContext) private var modelContext
    
    // 按顺序查询所有科目
    @Query(sort: \Subject.order) private var subjects: [Subject]
    
    @State private var newSubjectName = ""
    
    var body: some View {
        List {
            Section(footer: Text("长按并拖拽可调整科目显示顺序")) {
                ForEach(subjects) { subject in
                    Text(subject.name)
                }
                .onDelete(perform: deleteSubjects)
                .onMove(perform: moveSubjects)
            }
            
            Section {
                HStack {
                    TextField("新建科目名称...", text: $newSubjectName)
                    Button("添加") {
                        addSubject()
                    }
                    .disabled(newSubjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("科目管理")
        .toolbar {
            EditButton()
        }
    }
    
    private func addSubject() {
        let name = newSubjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        // 避免重复添加
        if subjects.contains(where: { $0.name == name }) {
            newSubjectName = ""
            return
        }
        
        // 自动排在最后
        let newOrder = (subjects.last?.order ?? -1) + 1
        let subject = Subject(name: name, order: newOrder)
        modelContext.insert(subject)
        newSubjectName = ""
    }
    
    private func deleteSubjects(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(subjects[index])
        }
    }
    
    private func moveSubjects(from source: IndexSet, to destination: Int) {
        var revisedItems = subjects
        revisedItems.move(fromOffsets: source, toOffset: destination)
        
        // 更新数据库中的顺序
        for (index, item) in revisedItems.enumerated() {
            item.order = index
        }
    }
}
