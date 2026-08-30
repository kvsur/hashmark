//
//  AboutView.swift
//  MarkdownApp
//
//  关于：展示开发者联系方式与审核要求的法律入口。
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let email = "hello1024lc@gmail.com"

    var body: some View {
        NavigationStack {
            Form {
                Section("Developer") {
                    LabeledContent("Contact Email") {
                        // mailto 链接：点击唤起系统邮件；URL 常量固定，强解包安全。
                        Link(email, destination: URL(string: "mailto:\(email)")!)
                    }
                }

                Section("Legal") {
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .rebuildsOnLanguageChange()
    }
}
