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
            WritingDeskTimelineNode(title: "排队", value: snapshot.queue)
            WritingDeskTimelineNode(title: "生成", value: snapshot.generate)
            WritingDeskTimelineNode(title: "收尾", value: snapshot.finish)
            WritingDeskTimelineNode(title: "完成", value: snapshot.complete)
        }
    }
}

struct WritingDeskTimelineNode: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1fs", value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.16)
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
