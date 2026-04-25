import AppKit
import SwiftUI

struct WritingDeskCollapsedLayout {
    static let configurationCardHeight: CGFloat = 74

    let creationRowHeight: CGFloat
    let draftPrimaryCardHeight: CGFloat
    let cacheCardHeight: CGFloat?
    let draftEditorHeight: CGFloat
    let cacheEditorHeight: CGFloat
    let aiCardHeight: CGFloat
    let aiEditorHeight: CGFloat

    init(
        containerSize: CGSize,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        spacing: CGFloat,
        showCachePanel: Bool,
        showTimeline: Bool
    ) {
        let availableHeight = max(280, containerSize.height - topPadding - bottomPadding - Self.configurationCardHeight - spacing)
        creationRowHeight = availableHeight
        aiCardHeight = availableHeight

        if showCachePanel {
            let proposedCacheHeight = min(max(128, availableHeight * 0.22), 196)
            cacheCardHeight = proposedCacheHeight
            draftPrimaryCardHeight = max(200, availableHeight - spacing - proposedCacheHeight)
        } else {
            cacheCardHeight = nil
            draftPrimaryCardHeight = availableHeight
        }

        draftEditorHeight = max(132, draftPrimaryCardHeight - 340)
        cacheEditorHeight = max(72, (cacheCardHeight ?? 0) - 124)
        aiEditorHeight = max(148, aiCardHeight - (showTimeline ? 272 : 214))
    }
}

struct WritingDeskInlineField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WritingDeskTextSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, weight: .regular))
            .scrollContentBackground(.hidden)
            .padding(14)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }
}

struct WritingDeskDraftSelection: Equatable {
    var range: NSRange
    var text: String

    static let empty = WritingDeskDraftSelection(range: NSRange(location: 0, length: 0), text: "")

    var hasSelection: Bool {
        range.length > 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct WritingDeskDraftEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: WritingDeskDraftSelection
    @Binding var selectionActionPoint: CGPoint?
    let focusToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: 16)
        textView.string = text

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applySelectionUpdate(from: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            context.coordinator.isApplyingProgrammaticChange = true
            textView.string = text
            context.coordinator.isApplyingProgrammaticChange = false
        }

        let safeRange = context.coordinator.safeSelectionRange(selection.range, in: textView.string as NSString)
        if textView.selectedRange() != safeRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.setSelectedRange(safeRange)
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        let resolvedActionPoint = context.coordinator.selectionActionPoint(for: safeRange, in: scrollView)
        if context.coordinator.parent.selectionActionPoint != resolvedActionPoint {
            context.coordinator.parent.selectionActionPoint = resolvedActionPoint
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        context.coordinator.applySelectionUpdate(from: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingDeskDraftEditor
        weak var textView: NSTextView?
        var isApplyingProgrammaticChange = false
        var isApplyingProgrammaticSelection = false
        var lastFocusToken: UUID?

        init(parent: WritingDeskDraftEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView
            else { return }

            let updatedText = textView.string
            if parent.text != updatedText {
                parent.text = updatedText
            }

            applySelectionUpdate(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticSelection,
                  let textView
            else { return }
            applySelectionUpdate(from: textView)
        }

        func applySelectionUpdate(from textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let nsText = textView.string as NSString
            let safeRange = safeSelectionRange(selectedRange, in: nsText)
            let selectedText = safeRange.length > 0 ? nsText.substring(with: safeRange) : ""
            let resolvedSelection = WritingDeskDraftSelection(range: safeRange, text: selectedText)

            if parent.selection != resolvedSelection {
                parent.selection = resolvedSelection
            }
        }

        func safeSelectionRange(_ range: NSRange, in text: NSString) -> NSRange {
            let safeLocation = min(max(range.location, 0), text.length)
            let safeLength = min(max(range.length, 0), max(0, text.length - safeLocation))
            return NSRange(location: safeLocation, length: safeLength)
        }

        func selectionActionPoint(for range: NSRange, in scrollView: NSScrollView) -> CGPoint? {
            guard range.length > 0,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return nil }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }

            var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let textContainerOrigin = textView.textContainerOrigin
            selectionRect.origin.x += textContainerOrigin.x
            selectionRect.origin.y += textContainerOrigin.y

            let visibleRect = textView.visibleRect
            let clippedRect = selectionRect.intersection(visibleRect)
            guard !clippedRect.isNull, !clippedRect.isEmpty else { return nil }

            let clipView = scrollView.contentView
            let rectInClipView = textView.convert(clippedRect, to: clipView)
            return CGPoint(x: rectInClipView.maxX, y: rectInClipView.minY)
        }
    }
}

struct WritingDeskCacheSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(14)
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        .scrollIndicators(.visible)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }
}

struct WritingDeskTimelineRow: View {
    let snapshot: AIWriterTimingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            WritingDeskTimelineNode(stage: .queue, snapshot: snapshot)
            WritingDeskTimelineNode(stage: .generate, snapshot: snapshot)
            WritingDeskTimelineNode(stage: .finish, snapshot: snapshot)
            WritingDeskTimelineNode(stage: .complete, snapshot: snapshot)
        }
    }
}

enum AIWriterTimelineStage: Int, CaseIterable {
    case queue
    case generate
    case finish
    case complete

    var title: String {
        switch self {
        case .queue:
            return "排队"
        case .generate:
            return "生成"
        case .finish:
            return "收尾"
        case .complete:
            return "完成"
        }
    }
}

struct WritingDeskTimelineNode: View {
    @Environment(\.colorScheme) private var colorScheme
    let stage: AIWriterTimelineStage
    let snapshot: AIWriterTimingSnapshot

    var body: some View {
        VStack(spacing: 6) {
            Text(stage.title)
                .font(.headline)
                .foregroundStyle(textColor)

            Text(String(format: "%.1fs", value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textColor)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var value: Double {
        switch stage {
        case .queue:
            return snapshot.queue
        case .generate:
            return snapshot.generate
        case .finish:
            return snapshot.finish
        case .complete:
            return snapshot.complete
        }
    }

    private var isActive: Bool {
        snapshot.activeStage == stage && !snapshot.isStopping
    }

    private var isStopping: Bool {
        snapshot.activeStage == stage && snapshot.isStopping
    }

    private var isCompleted: Bool {
        guard let activeStage = snapshot.activeStage else { return value > 0 }
        return activeStage.rawValue > stage.rawValue || (activeStage == .complete && value > 0)
    }

    private var statusText: String {
        if isStopping {
            return "停止中"
        }

        if isActive {
            return "进行中"
        }

        if isCompleted {
            return "已完成"
        }

        return "等待中"
    }

    private var statusColor: Color {
        if isStopping {
            return .red
        }

        if isActive {
            return Color.blue
        }

        if isCompleted {
            return Color(red: 0.18, green: 0.68, blue: 0.40)
        }

        return .secondary
    }

    private var textColor: Color {
        if isActive || isCompleted || isStopping {
            return .primary
        }

        return .secondary
    }

    private var backgroundColor: some ShapeStyle {
        if isStopping {
            return AnyShapeStyle(Color.red.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }

        if isActive {
            return AnyShapeStyle(Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }

        if isCompleted {
            return AnyShapeStyle(Color.green.opacity(colorScheme == .dark ? 0.16 : 0.10))
        }

        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        if isStopping {
            return Color.red.opacity(0.5)
        }

        if isActive {
            return Color.blue.opacity(0.5)
        }

        if isCompleted {
            return Color.green.opacity(0.4)
        }

        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
    }
}

struct AIWriterThinkingState {
    let title: String
    let subtitle: String
    let messages: [String]
    let activeIndex: Int
    let isStopping: Bool
}

struct AIWriterThinkingSurface: View {
    let state: AIWriterThinkingState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    if state.isStopping {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.red)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(state.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(state.messages.enumerated()), id: \.offset) { index, message in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(dotColor(for: index))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(textColor(for: index))
                                .lineSpacing(3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index < state.activeIndex {
            return Color.green
        }

        if index == state.activeIndex {
            return state.isStopping ? Color.red : Color.blue
        }

        return .secondary.opacity(0.35)
    }

    private func textColor(for index: Int) -> Color {
        if index <= state.activeIndex {
            return .primary
        }

        return .secondary
    }
}

struct WritingDeskBounceLockView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private var liveScrollEndObserver: NSObjectProtocol?

        func attachIfNeeded(from view: NSView) {
            guard let discoveredScrollView = view.enclosingScrollView else { return }
            guard scrollView !== discoveredScrollView else { return }

            detach()
            scrollView = discoveredScrollView

            liveScrollEndObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: discoveredScrollView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.snapBackToTopIfNeeded()
                }
            }
        }

        func detach() {
            if let liveScrollEndObserver {
                NotificationCenter.default.removeObserver(liveScrollEndObserver)
            }

            liveScrollEndObserver = nil
            scrollView = nil
        }

        private func snapBackToTopIfNeeded() {
            guard let scrollView, let documentView = scrollView.documentView else { return }

            let clipView = scrollView.contentView
            let targetTopY = topOriginY(for: scrollView, documentView: documentView)
            let currentY = clipView.bounds.origin.y

            let needsSnapBack: Bool
            if documentView.isFlipped {
                needsSnapBack = currentY < targetTopY - 0.5
            } else {
                needsSnapBack = currentY > targetTopY + 0.5
            }

            guard needsSnapBack else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetTopY))
            }

            scrollView.reflectScrolledClipView(clipView)
        }

        private func topOriginY(for scrollView: NSScrollView, documentView: NSView) -> CGFloat {
            if documentView.isFlipped {
                return 0
            }

            let visibleHeight = scrollView.contentView.bounds.height
            let documentHeight = documentView.bounds.height
            return max(0, documentHeight - visibleHeight)
        }
    }
}
