import SwiftUI
import Supabase

struct SupabaseAuthView: View {
    @Environment(SupabaseManager.self) var supabaseManager
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var message = ""
    @State private var isError = false
    
    // 新增：用于切换 登录 和 注册 模式
    @State private var isLoginMode = true

    var body: some View {
        Form {
            Section {
                // 分段选择器，让用户明确意图
                Picker("模式", selection: $isLoginMode) {
                    Text("登录").tag(true)
                    Text("注册").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
            }
            
            Section(header: Text("账号信息"), footer: Text(isLoginMode ? "请输入您的注册邮箱和密码。" : "新用户注册后，请注意查收邮件验证（如果开启了邮件验证）。")) {
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                SecureField("密码", text: $password)
            }
            
            Section {
                Button(action: handleAuth) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(isLoginMode ? "立即登录" : "创建账号")
                            .fontWeight(.bold)
                        Spacer()
                    }
                }
                .disabled(isLoading || email.isEmpty || password.count < 6)
            }
            
            if !message.isEmpty {
                Section {
                    Text(message)
                        .foregroundColor(isError ? .red : .green)
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(isLoginMode ? "欢迎回来" : "加入 Pulse")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func handleAuth() {
        isLoading = true
        message = ""
        isError = false
        
        Task {
            do {
                if isLoginMode {
                    // 执行登录逻辑
                    try await supabaseManager.client.auth.signIn(email: email, password: password)
                    await refreshUser()
                    dismiss()
                } else {
                    // 执行注册逻辑
                    try await supabaseManager.client.auth.signUp(email: email, password: password)
                    message = "注册申请已提交！"
                    isError = false
                    
                    // 尝试刷新用户信息（有些配置下注册完会自动登录）
                    await refreshUser()
                    if supabaseManager.currentUser != nil {
                        dismiss()
                    } else {
                        message = "请前往邮箱验证您的账号后登录。"
                    }
                }
            } catch {
                isError = true
                // 优化错误提示信息
                let errorDescription = error.localizedDescription
                if errorDescription.contains("Invalid login credentials") {
                    message = "登录失败：邮箱或密码错误"
                } else if errorDescription.contains("User already registered") {
                    message = "该邮箱已被注册，请切换到登录模式"
                } else {
                    message = "操作失败: \(errorDescription)"
                }
                print("Auth Error: \(error)")
            }
            isLoading = false
        }
    }
    
    private func refreshUser() async {
        // 更新全局用户信息状态
        do {
            let session = try await supabaseManager.client.auth.session
            supabaseManager.currentUser = session.user
        } catch {
            supabaseManager.currentUser = nil
        }
    }
}
