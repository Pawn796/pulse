import SwiftUI

// MARK: - 顶部标题栏
struct HomeHeaderView: View {
    @Environment(SupabaseManager.self) var supabaseManager
    @Binding var showSettings: Bool
    @Binding var showAddNote: Bool
    
    var onStatusTap: () -> Void
    
    var body: some View {
        HStack(alignment: .center) {
            // 左侧：同步状态圆点
            if supabaseManager.currentUser != nil {
                Button(action: onStatusTap) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                }
                .padding(.leading, 8)
            } else {
                Spacer().frame(width: 12)
            }
            
            Spacer()
            
            // 右侧：设置与新增按钮
            HStack(spacing: 20) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                Button(action: { showAddNote = true }) {
                    Image(systemName: "plus")
                }
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.primary)
        }
        .padding(.horizontal)
        .padding(.top, 15)
        .padding(.bottom, 10)
    }
    
    private var statusColor: Color {
        switch supabaseManager.syncStatus {
        case .synced: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }
}

// MARK: - 搜索与筛选控制栏
struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var showDateFilter: Bool
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 搜索框主体
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("搜索内容...", text: $searchText)
                    .focused($isFocused)
                    .submitLabel(.done)
                
                // 一键清空按钮：仅在有字符时显示
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        UIImpactFeedbackGenerator(style: .light).impactOccurred() // 触感反馈
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(.systemGray3))
                            .padding(.trailing, 4)
                    }
                    .transition(.opacity.combined(with: .scale)) // 缩放平滑过渡
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            // 当按钮出现/消失时，让布局平滑变化
            .animation(.spring(response: 0.3), value: searchText.isEmpty)
            
            // 优化后的筛选器按钮
            Button(action: {
                isFocused = false // 展开面板时收起键盘
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showDateFilter.toggle()
                }
            }) {
                Image(systemName: showDateFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(showDateFilter ? .white : .blue)
                    .padding(10)
                    .frame(width: 44, height: 44) // 固定点击区域
                    .background(
                        ZStack {
                            if showDateFilter {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.gradient) // 选中高亮
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            }
                        }
                    )
                    .scaleEffect(showDateFilter ? 1.05 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal)
    }
}

// MARK: - 科目筛选横向滚动栏
struct FilterBarView: View {
    let subjects: [Subject]
    @Binding var isFavSelected: Bool
    @Binding var selectedSubject: String?
    var onFilterTap: () -> Void
    
    private var itemWidth: CGFloat {
        (UIScreen.main.bounds.width - 32 - 40) / 6
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1.35) {
                filterButton(title: "收藏", isSelected: isFavSelected) {
                    onFilterTap()
                    withAnimation(.spring()) { isFavSelected.toggle() }
                }
                .frame(width: itemWidth)
                
                ForEach(subjects) { subject in
                    filterButton(title: subject.name, isSelected: selectedSubject == subject.name) {
                        onFilterTap()
                        withAnimation(.spring()) {
                            selectedSubject = (selectedSubject == subject.name) ? nil : subject.name
                        }
                    }
                    .frame(width: itemWidth)
                }
            }
            .padding(.horizontal, 0)
        }
    }
    
    @ViewBuilder
    func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if title == "收藏" {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .font(.system(size: 16))
                } else {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Color.yellow : Color(.systemBackground))
            .foregroundColor(isSelected ? .black : .primary)
            .cornerRadius(10)
            .shadow(color: isSelected ? Color.black.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - 自定义日期行 (修复版)
struct CustomDatePickerRow: View {
    let title: String
    @Binding var date: Date?
    var onDateTap: () -> Void
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let date = date {
                // 已选日期显示状态
                HStack(spacing: 8) {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    Button {
                        withAnimation { self.date = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            } else {
                // 未选状态
                // 🟢 恢复使用 ZStack，保留原来的布局意图（保证点击区域足够大）
                ZStack(alignment: .trailing) {
                    // 1. 视觉层：你希望用户看到的
                    Text("选择日期")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    // 2. 功能层：隐形的触摸层
                    DatePicker("", selection: Binding(get: { Date() }, set: {
                        self.date = $0
                        onDateTap()
                    }), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    // ⚠️ 核心修正：
                    // 不用 opacity(0.011)，因为 iPad 会忽略它。
                    // 改用 colorMultiply(.clear) 或者 blendMode。
                    // 这样系统认为它是“完全不透明”的（alpha=1），肯定能点，但它是透明色。
                    .colorMultiply(.clear)
                    // 额外加一层背景确保有点击面积，万一 DatePicker 收缩了
                    .background(Color.black.opacity(0.001))
                }
            }
        }
        .frame(height: 35)
        .contentShape(Rectangle()) // 确保整行空白处不遮挡点击
    }
}
