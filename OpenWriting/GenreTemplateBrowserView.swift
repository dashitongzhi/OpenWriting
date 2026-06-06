import SwiftUI

// MARK: - Genre Template Browser View

/// A full-screen browser for genre templates, with category sidebar,
/// template cards, and a detail pane. Integrates with NovelProject
/// via `selectedTemplateID` binding.
struct GenreTemplateBrowserView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// When set, the "使用此模板" button appears; selecting a template writes its id here.
    @Binding var selectedTemplateID: String?

    @State private var selectedCategory: GenreCategory = .xuanhuan
    @State private var selectedTemplate: GenreTemplate? = nil
    @State private var searchText: String = ""

    private var palette: DashboardPalette {
        DashboardPalette(colorScheme: colorScheme)
    }

    /// Templates filtered by category (and optional search).
    private var visibleTemplates: [GenreTemplate] {
        let inCategory = GenreTemplateLibrary.allTemplates.filter { $0.category == selectedCategory }
        guard !searchText.isEmpty else { return inCategory }
        let q = searchText.lowercased()
        return inCategory.filter {
            $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
            || $0.coreSellingPoint.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            PageBackground()

            HStack(spacing: 0) {
                // ── Sidebar ──
                sidebar
                    .frame(width: 200)

                Divider()
                    .overlay(palette.divider)

                // ── Template Cards ──
                templateCardColumn
                    .frame(minWidth: 300, idealWidth: 340)

                Divider()
                    .overlay(palette.divider)

                // ── Detail Pane ──
                detailPane
                    .frame(minWidth: 360, idealWidth: 420)
            }
        }
        .navigationTitle("题材模板库")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            // Pre-select the first template in the initial category
            if selectedTemplate == nil {
                selectedTemplate = visibleTemplates.first
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedTemplate = visibleTemplates.first
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("题材分类")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                TextField("搜索…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.insetPanel)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // Category list
            VStack(spacing: 4) {
                ForEach(GenreCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Template count
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text("\(GenreTemplateLibrary.allTemplates.count) 个模板")
                    .font(.caption)
            }
            .foregroundStyle(palette.textSecondary)
            .padding(12)
        }
        .background(palette.panelSecondary.opacity(palette.isDark ? 0.6 : 0.4))
    }

    private func categoryRow(_ category: GenreCategory) -> some View {
        let isSelected = selectedCategory == category
        // Count templates in this category that match the current search text,
        // so the sidebar reflects what the user can actually see.
        let q = searchText.lowercased()
        let count = GenreTemplateLibrary.allTemplates.filter { template in
            guard template.category == category else { return false }
            if q.isEmpty { return true }
            return template.name.lowercased().contains(q)
                || template.description.lowercased().contains(q)
                || template.coreSellingPoint.lowercased().contains(q)
        }.count

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 10) {
                // Category icon
                Image(systemName: categoryIcon(category))
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? palette.coolAccent : palette.textSecondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                    Text(category.genres.prefix(4).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(palette.badgeFill)
                    )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.selectedPanel : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ category: GenreCategory) -> String {
        switch category {
        case .xuanhuan: return "flame"
        case .urban:    return "building.2"
        case .romance:  return "heart"
        case .mystery:  return "eye"
        }
    }

    // MARK: - Template Card Column

    private var templateCardColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(selectedCategory.rawValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(visibleTemplates.count) 个模板")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            if visibleTemplates.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(palette.textSecondary.opacity(0.5))
                    Text("未找到匹配模板")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            templateCard(template)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(palette.panelBase.opacity(palette.isDark ? 0.3 : 0.2))
    }

    private func templateCard(_ template: GenreTemplate) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        let isActive = selectedTemplateID == template.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTemplate = template
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(alignment: .center, spacing: 8) {
                    Text(template.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)

                    if isActive {
                        Text("当前")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(palette.successAccent)
                            )
                    }

                    Spacer()

                    // Density badge
                    densityBadge(template.coolPointDensity)
                }

                // Core selling point
                Text(template.coreSellingPoint)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)

                // Tags row: hook types
                FlowLayout(spacing: 5) {
                    ForEach(template.preferredHookTypes, id: \.self) { hook in
                        tagChip(hook.displayName, color: palette.coolAccent)
                    }
                    ForEach(template.preferredCoolPointPatterns, id: \.self) { pattern in
                        tagChip(pattern.displayName, color: palette.warmAccent)
                    }
                }
            }
            .padding(14)
            .background(
                ZStack {
                    GlassPanelBackground(
                        cornerRadius: 14,
                        palette: palette,
                        tint: LinearGradient(
                            colors: isSelected
                                ? [palette.coolAccent.opacity(0.06), palette.coolAccent.opacity(0.02)]
                                : [Color.clear, Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.coolAccent.opacity(0.4) : palette.stroke,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: palette.shadow.opacity(isSelected ? 0.18 : 0.06),
                radius: isSelected ? 10 : 4,
                y: isSelected ? 4 : 2
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let template = selectedTemplate {
                detailContent(template)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "hand.tap")
                        .font(.system(size: 32))
                        .foregroundStyle(palette.textSecondary.opacity(0.4))
                    Text("选择一个模板查看详情")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.panelSecondary.opacity(palette.isDark ? 0.35 : 0.22))
    }

    private func detailContent(_ t: GenreTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Title section ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(t.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(palette.textPrimary)

                        Text(t.category.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.coolAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(palette.coolAccent.opacity(0.12))
                            )
                    }

                    Text(t.description)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineSpacing(3)

                    Text("核心卖点：\(t.coreSellingPoint)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.warmAccent)
                }

                // ── Use template button ──
                if selectedTemplateID != nil {
                    Button {
                        selectedTemplateID = t.id
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedTemplateID == t.id ? "checkmark.circle.fill" : "plus.circle")
                            Text(selectedTemplateID == t.id ? "已选用此模板" : "使用此模板")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedTemplateID == t.id ? palette.successAccent : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedTemplateID == t.id
                                      ? palette.successAccent.opacity(0.12)
                                      : palette.coolAccent)
                        )
                    }
                    .buttonStyle(.plain)
                }

                divider

                // ── Quick Stats ──
                quickStatsGrid(t)

                divider

                // ── Writing Directives ──
                detailSection(title: "写作指令", icon: "text.book.closed") {
                    ForEach(t.writingDirectives, id: \.self) { directive in
                        directiveRow(directive)
                    }
                }

                // ── Anti-Patterns ──
                detailSection(title: "避坑指南", icon: "exclamationmark.triangle") {
                    ForEach(t.antiPatterns, id: \.self) { pattern in
                        antiPatternRow(pattern)
                    }
                }

                divider

                // ── Strand Configuration ──
                detailSection(title: "节奏线配置", icon: "waveform.path") {
                    strandConfigGrid(t.strandConfig)
                }

                // ── Hook Types Detail ──
                detailSection(title: "钩子类型", icon: "point.3.connected.trianglepath.dotted") {
                    ForEach(t.preferredHookTypes, id: \.self) { hook in
                        hookDetailRow(hook)
                    }
                }

                // ── Cool Point Patterns Detail ──
                detailSection(title: "爽点模式", icon: "sparkles") {
                    ForEach(t.preferredCoolPointPatterns, id: \.self) { pattern in
                        coolPointRow(pattern)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Quick Stats Grid

    private func quickStatsGrid(_ t: GenreTemplate) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            statCard("钩子强度", value: t.hookStrengthBaseline.displayName,
                     icon: "bolt.fill", color: palette.warmAccent)
            statCard("爽点密度", value: t.coolPointDensity.displayName,
                     icon: "flame.fill", color: .orange)
            statCard("停顿阈值", value: "\(t.stagnationThreshold) 章",
                     icon: "clock.badge.exclamationmark", color: palette.coolAccent)
            statCard("铺垫容忍", value: "\(t.setupTolerance.displayName)（最多 \(t.setupTolerance.maxSetupChapters) 章）",
                     icon: "hourglass", color: palette.successAccent)
        }
    }

    private func statCard(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.insetPanel)
        )
    }

    // MARK: - Strand Config Grid

    private func strandConfigGrid(_ config: GenreStrandConfig) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                strandStat("任务线", target: config.questTarget, max: config.questMaxConsecutive, unit: "连章",
                           color: palette.coolAccent)
                strandStat("高潮线", target: config.fireTarget, max: config.fireMaxGap, unit: "间隔",
                           color: palette.warmAccent)
                strandStat("伏笔线", target: config.constellationTarget, max: config.constellationMaxGap, unit: "间隔",
                           color: palette.successAccent)
            }

            Text("Genre: \(config.genre)")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary.opacity(0.6))
        }
    }

    private func strandStat(_ label: String, target: Double, max: Int, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Text("目标 \(Int(target * 100))%")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
            Text("最大 \(max) \(unit)")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.insetPanel)
        )
    }

    // MARK: - Detail Section & Rows

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            content()
        }
    }

    private func directiveRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(palette.successAccent)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.insetPanel)
        )
    }

    private func antiPatternRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(palette.warmAccent)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.warmAccent.opacity(palette.isDark ? 0.06 : 0.04))
        )
    }

    private func hookDetailRow(_ hook: HookType) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(hook.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(palette.coolAccent)
                )
                .fixedSize()

            Text(hook.description)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.insetPanel)
        )
    }

    private func coolPointRow(_ pattern: CoolPointPattern) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(pattern.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(palette.warmAccent)
                    )

                Spacer()
            }

            Text(pattern.threePhaseStructure)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.insetPanel)
        )
    }

    // MARK: - Helpers

    private func tagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(palette.isDark ? 0.12 : 0.10))
            )
    }

    private func densityBadge(_ density: CoolPointDensity) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(densityLevel(density) > index ? palette.warmAccent : palette.textSecondary.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
            Text(density.displayName)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func densityLevel(_ density: CoolPointDensity) -> Int {
        switch density {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - Flow Layout (Tag Wrapping)

/// A simple flow layout that wraps children horizontally.
fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

// MARK: - Sheet Wrapper for standalone presentation

/// Presents GenreTemplateBrowserView in a sheet for project genre selection.
struct GenreTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID: String?
    @State private var hasInitialized = false

    let currentTemplateID: String?
    let onSelect: (String) -> Void

    var body: some View {
        GenreTemplateBrowserView(selectedTemplateID: $selectedTemplateID)
            .frame(minWidth: 860, minHeight: 560)
            .onAppear {
                // Seed with the current template once, and only once, so the
                // initial assignment doesn't fire onSelect().
                if !hasInitialized {
                    hasInitialized = true
                    selectedTemplateID = currentTemplateID
                }
            }
            .onChange(of: selectedTemplateID) { _, newValue in
                guard hasInitialized, let id = newValue else { return }
                onSelect(id)
            }
    }
}

// MARK: - Preview

#Preview("Genre Template Browser") {
    GenreTemplateBrowserView(selectedTemplateID: .constant("xianxia"))
        .frame(minWidth: 860, minHeight: 560)
}

#Preview("Genre Template Picker Sheet") {
    GenreTemplatePickerSheet(
        currentTemplateID: nil,
        onSelect: { _ in }
    )
}
