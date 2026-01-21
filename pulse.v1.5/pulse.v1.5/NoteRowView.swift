import SwiftUI
import SwiftData

struct NoteRowView: View {
    let note: Note
    let highlightText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if !note.tag.isEmpty {
                    Text(note.tag)
                        .font(.system(size: 10, weight: .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.05))
                        .foregroundColor(.secondary.opacity(0.7))
                        .cornerRadius(4)
                        .offset(y: -20)
                }
                Spacer()
                
                // 标志区域
                HStack(spacing: 8) {
                    // 🟢 置顶标志过渡动画
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            )) // 插入和移除时的缩放与透明度组合动画
                    }
                    
                    // 🟢 收藏标志过渡动画
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 16))
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            )) // 插入和移除时的缩放与透明度组合动画
                    }
                }
                // 使用响应式弹簧动画，使图标弹出更自然
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: note.isPinned)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: note.isFavorite)
            }
            
            highlightedText(content: note.content, query: highlightText)
                .font(.system(size: 17))
                .lineSpacing(5)
                .foregroundColor(.primary)
            
            HStack {
                Spacer()
                Text(note.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func highlightedText(content: String, query: String) -> Text {
        guard !query.isEmpty, content.localizedCaseInsensitiveContains(query) else {
            return Text(content)
        }
        
        let parts = content.components(separatedBy: query)
        var result = Text("")
        
        for (index, part) in parts.enumerated() {
            result = result + Text(part)
            if index < parts.count - 1 {
                result = result + Text(query).foregroundColor(.orange).bold()
            }
        }
        return result
    }
}
