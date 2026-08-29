//
//  AIWritingGenerationView.swift
//  MarkdownApp
//
//  只负责把会话状态呈现为推理、搜索、正文和恢复控件；输入阶段与 sheet 生命周期
//  仍由 AIWritingView 管理。
//

import SwiftUI

struct AIWritingGenerationView: View {
    @ObservedObject var session: AIWritingSession
    @Binding var streamingScroll: AIStreamingScrollState
    @Binding var scrollToLatestToken: Int
    @Binding var reasoningDisclosure: AIReasoningDisclosureState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let reason = session.interruptedReason {
                interruptedBanner(reason)
            }
            if shouldShowCompactStatus {
                AIGenerationStatusView(phase: session.presentationState.phase)
            }
            if session.hasReasoning {
                AIReasoningTraceView(
                    text: session.reasoningText,
                    state: reasoningTraceState,
                    isExpanded: reasoningExpandedBinding,
                    onDisclosureChange: {}
                )
            }
            if session.searchState != .idle || !session.citations.isEmpty {
                AISearchSourcesView(
                    state: session.searchState,
                    citations: session.citations
                )
            }
            if session.hasAnswer || session.presentationState.hasStartedAnswer {
                answerPreview
            } else {
                Spacer(minLength: 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.canAccept {
                AIRefineBar(
                    onRefine: { session.refine($0) },
                    onRegenerate: { session.regenerate() }
                )
            } else if session.presentationState.phase.isTerminal, session.hasContent {
                recoveryBar
            }
        }
    }

    private var answerPreview: some View {
        AIStreamingPreview(
            markdown: session.isStreaming ? session.text : session.finalText,
            isFinal: session.isDone,
            colorScheme: colorScheme,
            isFollowingBottom: followingBottomBinding,
            scrollToLatestToken: scrollToLatestToken
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if session.isStreaming && !streamingScroll.followsLatest {
                JumpToLatestButton {
                    streamingScroll.jumpToLatest()
                    scrollToLatestToken += 1
                }
                .padding(.bottom, 16)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(
            .spring(duration: 0.3),
            value: session.isStreaming && !streamingScroll.followsLatest
        )
    }

    private var reasoningTraceState: AIReasoningTraceView.State {
        session.presentationState.phase == .thinking ? .reasoning : .complete
    }

    private var shouldShowCompactStatus: Bool {
        switch session.presentationState.phase {
        case .thinking: !session.hasReasoning
        case .searching: session.searchState == .idle
        case .idle, .generating, .completed, .interrupted: false
        default: true
        }
    }

    private var reasoningExpandedBinding: Binding<Bool> {
        Binding(
            get: { reasoningDisclosure.isExpanded },
            set: { reasoningDisclosure.setExpanded($0) }
        )
    }

    private var followingBottomBinding: Binding<Bool> {
        Binding(
            get: { streamingScroll.followsLatest },
            set: { streamingScroll.readerPositionChanged(isNearBottom: $0) }
        )
    }

    private var recoveryBar: some View {
        HStack(spacing: 12) {
            Text("The partial answer won't be added to your document.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Try Again") { session.retry() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func interruptedBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation Interrupted")
                    .font(.subheadline.weight(.semibold))
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Retry") { session.retry() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}
