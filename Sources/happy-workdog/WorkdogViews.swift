import AppKit
import SwiftUI

enum PetWindowLayout {
    static let width: CGFloat = 330
    static let compactHeight: CGFloat = 420
    static let expandedHeight: CGFloat = 460
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 38
    static let stackSpacing: CGFloat = 8
    static let speechBubbleWidth: CGFloat = 238
    static let speechBubbleHeight: CGFloat = 58
    static let avatarSize: CGFloat = 220

    static var quickActionContentWidth: CGFloat {
        width - horizontalPadding * 2
    }

    static var avatarDragX: CGFloat {
        (width - avatarSize) / 2
    }

    static var avatarDragYFromTop: CGFloat {
        topPadding + speechBubbleHeight + stackSpacing
    }

    static func height(isPanelPresented: Bool) -> CGFloat {
        isPanelPresented ? expandedHeight : compactHeight
    }
}

struct PetRootView: View {
    @ObservedObject var store: WorkdogStore
    let onOpenSettings: () -> Void
    let onOpenClipboard: () -> Void
    let onTakeScreenshot: () -> Void
    let onOpenFavoriteEntry: (FavoriteEntry) -> Void
    let onRecordAction: (ReminderKind) -> Void

    @State private var floatPhase = false
    @State private var petPulse = false
    @State private var areSecondaryActionsExpanded = false
    @State private var secondaryActionStartIndex = 0
    @State private var messagePulse = false
    @State private var isPointerInside = false
    @GestureState private var secondaryActionDragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let quickActionCollapsedSpacing: CGFloat = 8
    private let pinnedQuickActionSize: CGFloat = 34
    private let secondaryQuickActionSize: CGFloat = 30
    private let secondaryQuickActionSpacing: CGFloat = 6

    private var isPanelPresented: Bool {
        store.isPomodoroPanelPresented || store.isFavoritesPanelPresented
    }

    private var petVisualOpacity: Double {
        isPointerInside && !isPanelPresented ? 0.88 : 1.0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: PetWindowLayout.stackSpacing) {
                SpeechBubbleView(text: store.currentMessage, tint: store.currentReminder.tint)
                    .frame(
                        width: PetWindowLayout.speechBubbleWidth,
                        height: PetWindowLayout.speechBubbleHeight,
                        alignment: .bottomLeading
                    )
                    .scaleEffect(messagePulse ? 1.035 : 1, anchor: .bottomLeading)
                    .offset(y: messagePulse ? -2 : 0)
                    .opacity(petVisualOpacity)

                DogAvatarView(
                    coat: store.coat,
                    shape: store.bodyShape,
                    mood: store.currentMood,
                    scale: store.avatarScale
                )
                .frame(width: PetWindowLayout.avatarSize, height: PetWindowLayout.avatarSize)
                .scaleEffect(petPulse ? 1.045 : 1.0)
                .offset(y: floatPhase ? -2 : 2)
                .opacity(petVisualOpacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    areSecondaryActionsExpanded = false
                    store.petDog()
                    playPetReaction()
                }
                .help("摸摸小狗")
                .accessibilityLabel("摸摸小狗")
                .onAppear {
                    startFloatingAnimation()
                }

                quickActions

                Spacer(minLength: 0)
            }

            if store.isFavoritesPanelPresented {
                FavoritesPanelView(store: store, onOpenSettings: onOpenSettings, onOpenEntry: { entry in
                    store.isFavoritesPanelPresented = false
                    onOpenFavoriteEntry(entry)
                }) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        store.isFavoritesPanelPresented = false
                    }
                }
                .frame(width: 286)
                .padding(.bottom, 18)
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }

            if store.isPomodoroPanelPresented {
                PomodoroClockPanelView(store: store) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        store.isPomodoroPanelPresented = false
                    }
                }
                .frame(width: 286)
                .padding(.bottom, 18)
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PetWindowLayout.horizontalPadding)
        .padding(.top, PetWindowLayout.topPadding)
        .frame(width: PetWindowLayout.width, height: PetWindowLayout.height(isPanelPresented: isPanelPresented))
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isPointerInside = hovering
            }
        }
        .onChange(of: reduceMotion) { _ in
            if reduceMotion {
                floatPhase = false
                messagePulse = false
                petPulse = false
            } else {
                startFloatingAnimation()
            }
        }
        .onChange(of: store.reminderPulse) { _ in
            playMessageReaction()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: store.isPomodoroPanelPresented)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: store.isFavoritesPanelPresented)
        .animation(.easeInOut(duration: 0.16), value: isPointerInside)
    }

    private func startFloatingAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
            floatPhase.toggle()
        }
    }

    private func playMessageReaction() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.72)) {
            messagePulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                messagePulse = false
            }
        }
    }

    private func playPetReaction() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
            petPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                petPulse = false
            }
        }
    }

    private var quickActions: some View {
        let isExpanded = areSecondaryActionsExpanded && !store.secondaryQuickActions.isEmpty

        return VStack(spacing: isExpanded ? 7 : 0) {
            HStack(spacing: quickActionCollapsedSpacing) {
                ForEach(store.pinnedQuickActions) { action in
                    quickActionButton(for: action, isPinned: true)
                }

                MoreQuickButton(isExpanded: areSecondaryActionsExpanded) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        store.isPomodoroPanelPresented = false
                        store.isFavoritesPanelPresented = false
                        if !areSecondaryActionsExpanded {
                            secondaryActionStartIndex = 0
                        }
                        areSecondaryActionsExpanded.toggle()
                    }
                }
            }

            if isExpanded {
                secondaryQuickActionCarousel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: areSecondaryActionsExpanded)
        .onChange(of: store.pinnedQuickActions) { _ in
            clampSecondaryActionStartIndex()
        }
        .onChange(of: store.pomodoroState) { _ in
            clampSecondaryActionStartIndex()
        }
    }

    private var secondaryQuickActionCarousel: some View {
        let actions = store.secondaryQuickActions
        let visibleCount = secondaryQuickActionVisibleCount
        let maxStartIndex = secondaryQuickActionMaxStartIndex
        let clampedStartIndex = min(secondaryActionStartIndex, maxStartIndex)
        let dragOffset = boundedSecondaryActionDragOffset(startIndex: clampedStartIndex, maxStartIndex: maxStartIndex)

        return HStack(spacing: secondaryQuickActionSpacing) {
            ForEach(actions) { action in
                quickActionButton(for: action, isPinned: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: -CGFloat(clampedStartIndex) * secondaryQuickActionStep + dragOffset)
        .frame(width: secondaryQuickActionSlotWidth(forVisibleCount: visibleCount), height: pinnedQuickActionSize, alignment: .leading)
        .contentShape(Rectangle())
        .clipped()
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .updating($secondaryActionDragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    updateSecondaryActionStartIndex(
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width
                    )
                }
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: secondaryActionStartIndex)
    }

    private var secondaryQuickActionVisibleCount: Int {
        let actionsCount = store.secondaryQuickActions.count
        guard actionsCount > 0 else { return 0 }

        let availableWidth = PetWindowLayout.quickActionContentWidth
        let wholeIconCount = Int(floor((availableWidth + secondaryQuickActionSpacing) / secondaryQuickActionStep))

        return min(actionsCount, min(4, max(1, wholeIconCount)))
    }

    private var secondaryQuickActionMaxStartIndex: Int {
        max(0, store.secondaryQuickActions.count - secondaryQuickActionVisibleCount)
    }

    private var secondaryQuickActionStep: CGFloat {
        secondaryQuickActionSize + secondaryQuickActionSpacing
    }

    private func secondaryQuickActionSlotWidth(forVisibleCount visibleCount: Int) -> CGFloat {
        guard visibleCount > 0 else { return 0 }
        return CGFloat(visibleCount) * secondaryQuickActionSize
            + CGFloat(visibleCount - 1) * secondaryQuickActionSpacing
    }

    private func boundedSecondaryActionDragOffset(startIndex: Int, maxStartIndex: Int) -> CGFloat {
        guard maxStartIndex > 0 else { return 0 }
        if startIndex == 0 && secondaryActionDragOffset > 0 {
            return secondaryActionDragOffset * 0.22
        }
        if startIndex == maxStartIndex && secondaryActionDragOffset < 0 {
            return secondaryActionDragOffset * 0.22
        }
        return secondaryActionDragOffset
    }

    private func updateSecondaryActionStartIndex(translation: CGFloat, predictedTranslation: CGFloat) {
        let maxStartIndex = secondaryQuickActionMaxStartIndex
        guard maxStartIndex > 0 else { return }

        let swipeDistance = abs(predictedTranslation) > abs(translation) ? predictedTranslation : translation
        let threshold = secondaryQuickActionStep * 0.42
        guard abs(swipeDistance) >= threshold else { return }

        let offset = swipeDistance < 0 ? 1 : -1
        let nextIndex = min(max(secondaryActionStartIndex + offset, 0), maxStartIndex)
        guard nextIndex != secondaryActionStartIndex else { return }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            secondaryActionStartIndex = nextIndex
        }
    }

    private func clampSecondaryActionStartIndex() {
        let maxStartIndex = secondaryQuickActionMaxStartIndex
        if secondaryActionStartIndex > maxStartIndex {
            secondaryActionStartIndex = maxStartIndex
        }
    }

    @ViewBuilder
    private func quickActionButton(for action: QuickAction, isPinned: Bool) -> some View {
        if action == .pomodoro {
            pomodoroQuickActionButton(isPinned: isPinned)
        } else if action == .favorites {
            favoritesQuickActionButton(isPinned: isPinned)
        } else {
            QuickActionButton(action: action, size: isPinned ? 34 : 30, iconSize: isPinned ? 14 : 13, showsShadow: isPinned) {
                if isPinned {
                    performPrimaryAction(action)
                } else {
                    performSecondaryAction {
                        runQuickAction(action)
                    }
                }
            }
        }
    }

    private func favoritesQuickActionButton(isPinned: Bool) -> some View {
        QuickActionButton(action: .favorites, size: isPinned ? 34 : 30, iconSize: isPinned ? 14 : 13, showsShadow: isPinned) {
            if isPinned {
                performPrimaryAction(.favorites)
            } else {
                performSecondaryAction {
                    runQuickAction(.favorites)
                }
            }
        }
    }

    @ViewBuilder
    private func pomodoroQuickActionButton(isPinned: Bool) -> some View {
        if store.pomodoroState == .idle {
            PomodoroQuickButton(store: store, size: isPinned ? 34 : 30, iconSize: isPinned ? 14 : 13, showsShadow: isPinned) {
                if isPinned {
                    performPrimaryAction(.pomodoro)
                } else {
                    performSecondaryAction {
                        runQuickAction(.pomodoro)
                    }
                }
            }
        } else {
            PomodoroCompactClockView(store: store, size: isPinned ? 48 : 34) {
                if isPinned {
                    performPrimaryAction(.pomodoro)
                } else {
                    performSecondaryAction {
                        runQuickAction(.pomodoro)
                    }
                }
            }
        }
    }

    private func performPrimaryAction(_ action: QuickAction) {
        areSecondaryActionsExpanded = false
        runQuickAction(action)
    }

    private func performSecondaryAction(_ action: () -> Void) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            areSecondaryActionsExpanded = false
        }
        action()
    }

    private func runQuickAction(_ action: QuickAction) {
        switch action {
        case .pomodoro:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                store.isFavoritesPanelPresented = false
                store.isPomodoroPanelPresented = true
            }
        case .favorites:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                store.isPomodoroPanelPresented = false
                store.isFavoritesPanelPresented.toggle()
            }
        case .clipboard:
            onOpenClipboard()
        case .screenshot:
            onTakeScreenshot()
        case .water:
            onRecordAction(.water)
        case .rest:
            onRecordAction(.rest)
        case .cheer:
            onRecordAction(.cheer)
        case .settings:
            onOpenSettings()
        }
    }
}

struct QuickActionButton: View {
    let action: QuickAction
    let size: CGFloat
    let iconSize: CGFloat
    let showsShadow: Bool
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            Image(systemName: action.symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(action.tint)
                .background(
                    Circle()
                        .fill(action.tint.opacity(0.16))
                        .overlay(
                            Circle().stroke(action.tint.opacity(0.28), lineWidth: 1)
                        )
                        .shadow(color: action.tint.opacity(showsShadow ? 0.12 : 0), radius: showsShadow ? 5 : 0, x: 0, y: showsShadow ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

struct MoreQuickButton: View {
    let isExpanded: Bool
    let action: () -> Void
    private let tint = Color(red: 0.44, green: 0.38, blue: 0.62)

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "xmark" : "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .foregroundStyle(tint)
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                        .overlay(
                            Circle().stroke(tint.opacity(0.28), lineWidth: 1)
                        )
                        .shadow(color: tint.opacity(0.12), radius: 5, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isExpanded ? "收起更多" : "更多")
        .accessibilityLabel(isExpanded ? "收起更多" : "更多")
    }
}

struct PomodoroQuickButton: View {
    @ObservedObject var store: WorkdogStore
    let size: CGFloat
    let iconSize: CGFloat
    let showsShadow: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(store.pomodoroMode.tint.opacity(0.14))
                    .overlay(
                        Circle().stroke(store.pomodoroMode.tint.opacity(0.22), lineWidth: 1)
                    )

                if store.pomodoroState != .idle {
                    Circle()
                        .trim(from: 0, to: store.pomodoroProgress)
                        .stroke(store.pomodoroMode.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }

                Image(systemName: "timer")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(store.pomodoroMode.tint)
            }
            .frame(width: size, height: size)
            .shadow(color: store.pomodoroMode.tint.opacity(showsShadow ? 0.12 : 0), radius: showsShadow ? 5 : 0, x: 0, y: showsShadow ? 2 : 0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("番茄钟")
        .accessibilityLabel("番茄钟")
    }
}

struct FavoritesPanelView: View {
    @ObservedObject var store: WorkdogStore
    let onOpenSettings: () -> Void
    let onOpenEntry: (FavoriteEntry) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var expandedFavoriteFolderIDs: Set<FavoriteEntry.ID> = []

    private let tint = Color(red: 0.76, green: 0.52, blue: 0.18)

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var visibleNodes: [FavoriteTreeNode] {
        guard isSearching else { return store.favoriteRootNodes }
        return filteredFavoriteNodes(store.favoriteRootNodes, query: trimmedSearchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("常用入口", systemImage: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .help("收起")
            }

            if store.favoriteEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("还没有入口")
                        .font(.system(size: 13, weight: .semibold))
                    Button {
                        onDismiss()
                        onOpenSettings()
                    } label: {
                        Label("去设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("搜索入口", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if visibleNodes.isEmpty {
                            Text("没有匹配的入口")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        } else {
                            ForEach(visibleNodes) { node in
                                FavoritePanelTreeNode(
                                    node: node,
                                    isSearching: isSearching,
                                    expandedFolderIDs: $expandedFavoriteFolderIDs,
                                    onOpenEntry: onOpenEntry
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
        )
    }

    private func filteredFavoriteNodes(_ nodes: [FavoriteTreeNode], query: String) -> [FavoriteTreeNode] {
        nodes.compactMap { node in
            let filteredChildren = filteredFavoriteNodes(node.children, query: query)
            let matches = node.entry.alias.localizedCaseInsensitiveContains(query)
                || node.entry.target.localizedCaseInsensitiveContains(query)
            guard matches || !filteredChildren.isEmpty else { return nil }
            return FavoriteTreeNode(entry: node.entry, children: filteredChildren)
        }
    }
}

private struct FavoritePanelTreeNode: View {
    let node: FavoriteTreeNode
    let isSearching: Bool
    @Binding var expandedFolderIDs: Set<FavoriteEntry.ID>
    let onOpenEntry: (FavoriteEntry) -> Void

    private var isExpanded: Bool {
        isSearching || expandedFolderIDs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if node.entry.isFolder {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 12)
                        Image(systemName: node.entry.kind.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(node.entry.alias)
                            .font(.system(size: 11, weight: .bold))
                        Text("\(node.children.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(node.children) { child in
                            FavoritePanelTreeNode(
                                node: child,
                                isSearching: isSearching,
                                expandedFolderIDs: $expandedFolderIDs,
                                onOpenEntry: onOpenEntry
                            )
                        }
                    }
                    .padding(.leading, 14)
                }
            } else {
                FavoriteEntryButton(entry: node.entry, action: {
                    onOpenEntry(node.entry)
                })
            }
        }
    }

    private func toggle() {
        guard !isSearching else { return }
        if expandedFolderIDs.contains(node.id) {
            expandedFolderIDs.remove(node.id)
        } else {
            expandedFolderIDs.insert(node.id)
        }
    }
}

private struct FavoriteEntryButton: View {
    let entry: FavoriteEntry
    let action: () -> Void

    private let tint = Color(red: 0.76, green: 0.52, blue: 0.18)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.alias)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.displayTarget)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(entry.alias)
    }
}

struct PomodoroCompactClockView: View {
    @ObservedObject var store: WorkdogStore
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PomodoroClockFace(store: store, size: size, showsModeLabel: false)
                .shadow(color: store.pomodoroMode.tint.opacity(0.14), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("打开番茄钟")
        .accessibilityLabel("打开番茄钟")
    }
}

struct PomodoroClockPanelView: View {
    @ObservedObject var store: WorkdogStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(store.pomodoroMode.title, systemImage: store.pomodoroMode.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.pomodoroMode.tint)

                Text(store.pomodoroStateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .help("收起")
            }

            HStack(spacing: 14) {
                PomodoroClockFace(store: store, size: 126, showsModeLabel: true)

                VStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(PomodoroMode.allCases) { mode in
                            Button {
                                store.selectPomodoroMode(mode)
                            } label: {
                                Image(systemName: mode.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 29, height: 28)
                                    .foregroundStyle(store.pomodoroMode == mode ? Color.white : mode.tint)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(store.pomodoroMode == mode ? mode.tint : mode.tint.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help(mode.title)
                        }
                    }

                    Button(action: store.togglePomodoro) {
                        Image(systemName: store.pomodoroPrimaryActionSymbol)
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color.white)
                            .background(
                                Circle()
                                    .fill(store.pomodoroMode.tint)
                                    .shadow(color: store.pomodoroMode.tint.opacity(0.24), radius: 8, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(store.pomodoroPrimaryActionTitle)

                    HStack(spacing: 8) {
                        Button(action: store.resetPomodoro) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                        .controlSize(.small)
                        .help("重置")

                        Button(action: store.skipPomodoroSegment) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                        .controlSize(.small)
                        .help("下一段")
                    }

                    Text("累计专注 \(store.completedFocusCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 98)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(store.pomodoroMode.tint.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
        )
    }
}

struct PomodoroClockFace: View {
    @ObservedObject var store: WorkdogStore
    let size: CGFloat
    let showsModeLabel: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))
                .overlay(
                    Circle().stroke(store.pomodoroMode.tint.opacity(0.14), lineWidth: 1)
                )

            ClockTickMarks(tint: store.pomodoroMode.tint)
                .padding(size * 0.09)

            Circle()
                .stroke(store.pomodoroMode.tint.opacity(0.16), lineWidth: max(4, size * 0.07))
                .padding(size * 0.07)

            Circle()
                .trim(from: 0, to: store.pomodoroProgress)
                .stroke(
                    store.pomodoroMode.tint,
                    style: StrokeStyle(lineWidth: max(4, size * 0.07), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(size * 0.07)

            Capsule()
                .fill(store.pomodoroMode.tint.opacity(0.42))
                .frame(width: max(2, size * 0.025), height: size * 0.29)
                .offset(y: -size * 0.145)
                .rotationEffect(.degrees(store.pomodoroProgress * 360))

            Circle()
                .fill(store.pomodoroMode.tint)
                .frame(width: size * 0.07, height: size * 0.07)

            VStack(spacing: showsModeLabel ? 3 : 1) {
                Text(store.pomodoroTimeText)
                    .font(.system(size: showsModeLabel ? 24 : 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.14, green: 0.15, blue: 0.18))

                if showsModeLabel {
                    Text(store.pomodoroMode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: store.pomodoroMode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(store.pomodoroMode.tint)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, showsModeLabel ? 4 : 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(showsModeLabel ? 0.78 : 0.68))
            )
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.2), value: store.pomodoroProgress)
    }
}

private struct ClockTickMarks: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    let isMajor = index % 3 == 0
                    Capsule()
                        .fill(isMajor ? tint.opacity(0.44) : Color.primary.opacity(0.16))
                        .frame(width: isMajor ? 2.4 : 1.6, height: isMajor ? 9 : 6)
                        .offset(y: -(radius - 5))
                        .rotationEffect(.degrees(Double(index) * 30))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct SpeechBubbleView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12.8, weight: .semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .multilineTextAlignment(.leading)
            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.22))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                Color.white.opacity(0.86),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(tint.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.08), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
            )
        .overlay(alignment: .bottomLeading) {
            BubbleTail(tint: tint)
                .frame(width: 22, height: 15)
                .offset(x: 22, y: 9)
        }
        .animation(.easeInOut(duration: 0.18), value: text)
    }
}

struct BubbleTail: View {
    let tint: Color

    var body: some View {
        BubbleTailShape()
            .fill(Color.white.opacity(0.88))
            .overlay(
                BubbleTailShape()
                    .stroke(tint.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 2.5, x: 0, y: 1.5)
    }
}

private struct BubbleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.1))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.88),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.3),
            control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.68),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.46)
        )
        path.closeSubpath()
        return path
    }
}

struct DogAvatarView: View {
    let coat: DogCoat
    let shape: DogShape
    let mood: DogMood
    let scale: Double

    @State private var breathPhase = false
    @State private var tailWagPhase = false
    @State private var blinkPhase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DogIllustrationView(
            coat: coat,
            shape: shape,
            mood: mood,
            tailWagPhase: tailWagPhase,
            blinkPhase: blinkPhase
        )
        .scaleEffect(CGFloat(scale) * (reduceMotion ? 1 : (breathPhase ? 1.02 : 0.98)))
        .offset(y: moodBounceOffset)
        .animation(.easeInOut(duration: 0.4), value: mood)
        .animation(.easeInOut(duration: 0.25), value: coat.id)
        .animation(.easeInOut(duration: 0.25), value: shape.id)
        .onAppear {
            startBreathing()
            startTailWag()
        }
        .onChange(of: mood) { _ in
            startTailWag()
        }
        .onChange(of: reduceMotion) { _ in
            if reduceMotion {
                breathPhase = false
                tailWagPhase = false
                blinkPhase = false
            } else {
                startBreathing()
                startTailWag()
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.08)) {
                        blinkPhase = true
                    }
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        blinkPhase = false
                    }
                }
            }
        }
    }

    private var moodBounceOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch mood {
        case .energized:
            return tailWagPhase ? -2 : 1
        case .proud:
            return tailWagPhase ? -1.5 : 0.5
        case .happy:
            return tailWagPhase ? -0.8 : 0.4
        case .idle:
            return 0
        }
    }

    private var tailDuration: Double {
        switch mood {
        case .energized: return 0.34
        case .proud: return 0.48
        case .happy: return 0.68
        case .idle: return 0.92
        }
    }

    private func startBreathing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            breathPhase.toggle()
        }
    }

    private func startTailWag() {
        tailWagPhase = false
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: tailDuration).repeatForever(autoreverses: true)) {
            tailWagPhase = true
        }
    }
}

private struct DogIllustrationView: View {
    let coat: DogCoat
    let shape: DogShape
    let mood: DogMood
    let tailWagPhase: Bool
    let blinkPhase: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let factor = size / 250
            let metrics = shape.metrics.scaled(by: factor)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let bodyY = center.y + metrics.bodyYOffset + 4 * factor
            let headY = center.y + metrics.headYOffset - 3 * factor
            let legY = bodyY + metrics.bodyHeight / 2 + metrics.legHeight * 0.36
            let strokeWidth = max(1.2, 2.6 * factor)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.13))
                    .frame(width: metrics.bodyWidth * 1.34, height: 22 * factor)
                    .blur(radius: 4 * factor)
                    .position(x: center.x, y: legY + metrics.legHeight * 0.72)

                Circle()
                    .fill(coat.accent.opacity(0.16))
                    .frame(width: metrics.headSize * 1.52, height: metrics.headSize * 1.52)
                    .blur(radius: 18 * factor)
                    .position(x: center.x, y: headY + metrics.headSize * 0.16)

                tail(metrics: metrics, strokeWidth: strokeWidth)
                    .rotationEffect(.degrees(tailAngle))
                    .animation(.easeInOut(duration: mood == .energized ? 0.34 : 0.82), value: tailWagPhase)
                    .position(
                        x: center.x + metrics.bodyWidth / 2 + metrics.tailLength * 0.42,
                        y: bodyY - metrics.bodyHeight * 0.28
                    )

                rearPaw(metrics: metrics, factor: factor)
                    .position(x: center.x - metrics.bodyWidth * 0.31, y: legY)

                rearPaw(metrics: metrics, factor: factor)
                    .position(x: center.x + metrics.bodyWidth * 0.31, y: legY)

                RoundedRectangle(cornerRadius: metrics.bodyCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [coat.highlight, coat.body, coat.shadow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.bodyCornerRadius, style: .continuous)
                            .stroke(coat.outline.opacity(0.35), lineWidth: strokeWidth)
                    )
                    .frame(width: metrics.bodyWidth * 0.94, height: metrics.bodyHeight * 0.88)
                    .position(x: center.x, y: bodyY)
                    .shadow(color: coat.shadow.opacity(0.22), radius: 8 * factor, x: 0, y: 6 * factor)

                Ellipse()
                    .fill(coat.belly.opacity(0.92))
                    .frame(width: metrics.bodyWidth * 0.5, height: metrics.bodyHeight * 0.5)
                    .position(x: center.x, y: bodyY + metrics.bodyHeight * 0.1)

                frontPaw(metrics: metrics, factor: factor, isLeft: true)
                    .position(x: center.x - metrics.bodyWidth * 0.23, y: bodyY + metrics.bodyHeight * 0.4)

                frontPaw(metrics: metrics, factor: factor, isLeft: false)
                    .position(x: center.x + metrics.bodyWidth * 0.23, y: bodyY + metrics.bodyHeight * 0.4)

                bandana(metrics: metrics, centerX: center.x, bodyY: bodyY, factor: factor)

                ear(metrics: metrics, isLeft: true, angle: earAngle(isLeft: true))
                    .position(x: center.x - metrics.headSize * 0.39, y: headY - metrics.headSize * 0.2)

                ear(metrics: metrics, isLeft: false, angle: earAngle(isLeft: false))
                    .position(x: center.x + metrics.headSize * 0.39, y: headY - metrics.headSize * 0.2)

                RoundedRectangle(cornerRadius: headCornerRadius(metrics), style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [coat.highlight, coat.body, coat.body, coat.shadow.opacity(0.96)],
                            center: UnitPoint(x: 0.3, y: 0.18),
                            startRadius: 6 * factor,
                            endRadius: metrics.headSize * 0.86
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: headCornerRadius(metrics), style: .continuous)
                            .stroke(coat.outline.opacity(0.34), lineWidth: strokeWidth)
                    )
                    .frame(width: metrics.headSize * 1.12, height: metrics.headSize * headHeightRatio * 1.04)
                    .position(x: center.x, y: headY)
                    .shadow(color: coat.shadow.opacity(0.2), radius: 7 * factor, x: 0, y: 5 * factor)

                FurTuftShape()
                    .fill(coat.highlight.opacity(0.82))
                    .frame(width: metrics.headSize * 0.42, height: metrics.headSize * 0.24)
                    .rotationEffect(.degrees(shape == .sleek ? -6 : 0))
                    .position(x: center.x, y: headY - metrics.headSize * 0.51)

                Ellipse()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: metrics.headSize * 0.3, height: metrics.headSize * 0.16)
                    .rotationEffect(.degrees(-25))
                    .position(x: center.x - metrics.headSize * 0.2, y: headY - metrics.headSize * 0.28)

                Ellipse()
                    .fill(coat.belly)
                    .overlay(
                        Ellipse()
                            .stroke(coat.outline.opacity(0.08), lineWidth: strokeWidth * 0.7)
                    )
                    .frame(width: metrics.headSize * 0.58, height: metrics.headSize * 0.39)
                    .position(x: center.x, y: headY + metrics.headSize * 0.14)

                face(metrics: metrics, centerX: center.x, headY: headY, factor: factor)

                moodAccent(factor: factor)
                    .position(x: center.x + metrics.headSize * 0.57, y: headY - metrics.headSize * 0.5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var tailAngle: Double {
        let wag = tailWagPhase ? 6.0 : -5.0
        switch mood {
        case .happy, .proud: return -34 + wag
        case .energized: return -42 + wag * 1.4
        case .idle: return -18 + wag * 0.6
        }
    }

    private func earAngle(isLeft: Bool) -> Double {
        let sign = isLeft ? -1.0 : 1.0
        switch mood {
        case .energized:
            return sign * 10
        case .proud:
            return sign * 14
        case .happy:
            return sign * 18
        case .idle:
            return sign * 23
        }
    }

    private var headHeightRatio: CGFloat {
        switch shape {
        case .sleek: return 0.9
        case .compact: return 0.95
        case .round, .fluffy: return 1.0
        }
    }

    private func headCornerRadius(_ metrics: DogMetrics) -> CGFloat {
        switch shape {
        case .sleek: return metrics.headSize * 0.32
        case .compact: return metrics.headSize * 0.38
        case .round, .fluffy: return metrics.headSize * 0.44
        }
    }

    private var moodColor: Color {
        switch mood {
        case .happy: return Color(red: 1.0, green: 0.4, blue: 0.48)
        case .energized: return Color(red: 1.0, green: 0.64, blue: 0.16)
        case .proud: return Color(red: 0.3, green: 0.58, blue: 0.96)
        case .idle: return Color(red: 0.22, green: 0.5, blue: 0.74)
        }
    }

    private func tail(metrics: DogMetrics, strokeWidth: CGFloat) -> some View {
        TailShape()
            .stroke(
                LinearGradient(
                    colors: [coat.highlight, coat.body, coat.shadow],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: max(10, metrics.tailLength * 0.36), lineCap: .round)
            )
            .overlay(
                TailShape()
                    .stroke(coat.outline.opacity(0.28), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            )
            .frame(width: metrics.tailLength * 1.55, height: metrics.tailLength * 0.95)
    }

    private func ear(metrics: DogMetrics, isLeft: Bool, angle: Double) -> some View {
        FloppyEarShape()
            .fill(
                LinearGradient(
                    colors: [coat.ear, coat.ear, coat.shadow],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            )
            .overlay(
                FloppyEarShape()
                    .inset(by: metrics.earWidth * 0.22)
                    .fill(coat.accent.opacity(0.32))
                    .padding(.top, metrics.earHeight * 0.16)
                    .padding(.bottom, metrics.earHeight * 0.2)
            )
            .overlay(
                FloppyEarShape()
                    .stroke(coat.outline.opacity(0.3), lineWidth: max(1.2, metrics.earWidth * 0.08))
            )
            .frame(width: metrics.earWidth * 1.35, height: metrics.earHeight * 1.08)
            .rotationEffect(.degrees(angle))
            .scaleEffect(x: isLeft ? 1 : -1, y: 1)
    }

    private func rearPaw(metrics: DogMetrics, factor: CGFloat) -> some View {
        let pawWidth = metrics.bodyWidth * 0.19
        let pawHeight = metrics.legHeight * 1.1
        let insetX = metrics.bodyWidth * 0.035
        let insetTop = metrics.legHeight * 0.46

        return Capsule()
            .fill(coat.shadow.opacity(0.8))
            .frame(width: pawWidth, height: pawHeight)
            .overlay {
                Capsule()
                    .fill(coat.belly.opacity(0.32))
                    .padding(.top, insetTop)
                    .padding(.horizontal, insetX)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 2 * factor, x: 0, y: factor)
    }

    private func frontPaw(metrics: DogMetrics, factor: CGFloat, isLeft: Bool) -> some View {
        let width = metrics.bodyWidth * 0.32
        let height = metrics.legHeight * 2.55
        let legWidth = metrics.bodyWidth * 0.15
        let legHeight = metrics.legHeight * 1.45
        let footWidth = metrics.bodyWidth * 0.28
        let footHeight = metrics.legHeight * 1.05
        let toeSize = max(4.2, 5.6 * factor)
        let padWidth = footWidth * 0.38
        let padHeight = footHeight * 0.34
        let highlightWidth = footWidth * 0.34
        let tilt = isLeft ? -4.0 : 4.0

        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(width: footWidth * 1.08, height: footHeight * 0.42)
                .blur(radius: 1.5 * factor)
                .position(x: width / 2, y: height - footHeight * 0.05)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            coat.highlight.opacity(0.92),
                            coat.body.opacity(0.95),
                            coat.shadow.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(coat.outline.opacity(0.18), lineWidth: max(1, 1.2 * factor))
                )
                .frame(width: legWidth, height: legHeight)
                .position(x: width / 2, y: legHeight * 0.52)

            Capsule()
                .fill(
                    RadialGradient(
                        colors: [
                            coat.belly,
                            coat.body.opacity(0.92),
                            coat.shadow.opacity(0.62),
                        ],
                        center: UnitPoint(x: 0.32, y: 0.2),
                        startRadius: 1 * factor,
                        endRadius: footWidth * 0.78
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(coat.outline.opacity(0.24), lineWidth: max(1, 1.4 * factor))
                )
                .frame(width: footWidth, height: footHeight)
                .rotationEffect(.degrees(tilt))
                .position(x: width / 2, y: height - footHeight * 0.46)

            Ellipse()
                .fill(Color.white.opacity(0.24))
                .frame(width: highlightWidth, height: footHeight * 0.22)
                .rotationEffect(.degrees(-18 + tilt))
                .position(x: width / 2 - footWidth * 0.16, y: height - footHeight * 0.72)

            HStack(spacing: max(1.8, 2.4 * factor)) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(coat.outline.opacity(index == 1 ? 0.36 : 0.28))
                        .frame(width: toeSize, height: toeSize * 0.92)
                        .overlay {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: toeSize * 0.38, height: toeSize * 0.3)
                                .offset(x: -toeSize * 0.12, y: -toeSize * 0.12)
                        }
                }
            }
            .rotationEffect(.degrees(tilt))
            .position(x: width / 2, y: height - footHeight * 0.66)

            Capsule()
                .fill(coat.outline.opacity(0.28))
                .frame(width: padWidth, height: padHeight)
                .overlay {
                    Ellipse()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: padWidth * 0.5, height: padHeight * 0.34)
                        .offset(x: -padWidth * 0.14, y: -padHeight * 0.16)
                }
                .rotationEffect(.degrees(tilt))
                .position(x: width / 2, y: height - footHeight * 0.34)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func bandana(metrics: DogMetrics, centerX: CGFloat, bodyY: CGFloat, factor: CGFloat) -> some View {
        let color = moodColor

        Capsule()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.45), lineWidth: max(1, 1.4 * factor))
            )
            .frame(width: metrics.bodyWidth * 0.66, height: max(10, 13 * factor))
            .position(x: centerX, y: bodyY - metrics.bodyHeight * 0.43)

        BandanaTailShape()
            .fill(color.opacity(0.82))
            .frame(width: 22 * factor, height: 24 * factor)
            .rotationEffect(.degrees(-8))
            .position(x: centerX + metrics.bodyWidth * 0.21, y: bodyY - metrics.bodyHeight * 0.34)
    }

    @ViewBuilder
    private func face(metrics: DogMetrics, centerX: CGFloat, headY: CGFloat, factor: CGFloat) -> some View {
        let eyeColor = Color(red: 0.12, green: 0.09, blue: 0.08)
        let eyeY = headY - metrics.headSize * 0.08
        let eyeOffset = metrics.headSize * 0.23
        let eyeWidth = metrics.headSize * 0.15
        let eyeHeight = metrics.headSize * 0.18

        if blinkPhase {
            Capsule()
                .fill(eyeColor.opacity(0.85))
                .frame(width: metrics.headSize * 0.2, height: max(2, 2.7 * factor))
                .rotationEffect(.degrees(-11))
                .position(x: centerX - eyeOffset, y: eyeY)

            Capsule()
                .fill(eyeColor.opacity(0.85))
                .frame(width: metrics.headSize * 0.2, height: max(2, 2.7 * factor))
                .rotationEffect(.degrees(11))
                .position(x: centerX + eyeOffset, y: eyeY)
        } else {
            cuteEye(width: eyeWidth, height: eyeHeight)
                .position(x: centerX - eyeOffset, y: eyeY)

            cuteEye(width: eyeWidth, height: eyeHeight)
                .position(x: centerX + eyeOffset, y: eyeY)
        }

        Image(systemName: "heart.fill")
            .font(.system(size: metrics.headSize * 0.115, weight: .black))
            .foregroundStyle(eyeColor)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: metrics.headSize * 0.024, height: metrics.headSize * 0.018)
                    .offset(x: -metrics.headSize * 0.026, y: -metrics.headSize * 0.024)
            )
            .position(x: centerX, y: headY + metrics.headSize * 0.08)

        SmileShape(depth: mood == .idle ? 0.3 : 0.48)
            .stroke(eyeColor.opacity(0.7), style: StrokeStyle(lineWidth: max(2, 2.4 * factor), lineCap: .round))
            .frame(width: metrics.headSize * 0.28, height: metrics.headSize * 0.17)
            .position(x: centerX, y: headY + metrics.headSize * 0.18)

        Circle()
            .fill(Color(red: 1.0, green: 0.45, blue: 0.42).opacity(0.32))
            .frame(width: metrics.headSize * 0.17, height: metrics.headSize * 0.1)
            .blur(radius: 0.4 * factor)
            .position(x: centerX - metrics.headSize * 0.35, y: headY + metrics.headSize * 0.11)

        Circle()
            .fill(Color(red: 1.0, green: 0.45, blue: 0.42).opacity(0.32))
            .frame(width: metrics.headSize * 0.17, height: metrics.headSize * 0.1)
            .blur(radius: 0.4 * factor)
            .position(x: centerX + metrics.headSize * 0.35, y: headY + metrics.headSize * 0.11)
    }

    private func cuteEye(width: CGFloat, height: CGFloat) -> some View {
        let eyeColor = Color(red: 0.12, green: 0.09, blue: 0.08)

        return ZStack {
            Ellipse()
                .fill(eyeColor)
                .frame(width: width, height: height)

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: width * 0.36, height: width * 0.36)
                .offset(x: width * 0.17, y: -height * 0.2)

            Circle()
                .fill(Color.white.opacity(0.36))
                .frame(width: width * 0.16, height: width * 0.16)
                .offset(x: -width * 0.18, y: height * 0.18)
        }
    }

    @ViewBuilder
    private func moodAccent(factor: CGFloat) -> some View {
        switch mood {
        case .happy:
            Image(systemName: "heart.fill")
                .font(.system(size: 19 * factor, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.34, blue: 0.42))
        case .energized:
            Image(systemName: "bolt.fill")
                .font(.system(size: 20 * factor, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.66, blue: 0.18))
        case .proud:
            Image(systemName: "sparkles")
                .font(.system(size: 20 * factor, weight: .bold))
                .foregroundStyle(Color(red: 0.28, green: 0.58, blue: 0.96))
        case .idle:
            EmptyView()
        }
    }
}

private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.28),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.78)
        )
        return path
    }
}

private struct FloppyEarShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.08))
        path.addCurve(
            to: CGPoint(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.76),
            control1: CGPoint(x: r.minX - r.width * 0.08, y: r.minY + r.height * 0.18),
            control2: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + r.height * 0.58)
        )
        path.addCurve(
            to: CGPoint(x: r.minX + r.width * 0.58, y: r.maxY - r.height * 0.04),
            control1: CGPoint(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.96),
            control2: CGPoint(x: r.minX + r.width * 0.46, y: r.minY + r.height * 1.02)
        )
        path.addCurve(
            to: CGPoint(x: r.minX + r.width * 0.88, y: r.minY + r.height * 0.18),
            control1: CGPoint(x: r.minX + r.width * 0.92, y: r.minY + r.height * 0.82),
            control2: CGPoint(x: r.minX + r.width * 1.02, y: r.minY + r.height * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.08),
            control1: CGPoint(x: r.minX + r.width * 0.7, y: r.minY + r.height * 0.02),
            control2: CGPoint(x: r.minX + r.width * 0.44, y: r.minY - r.height * 0.02)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FloppyEarShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct FurTuftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.12),
            control1: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.54),
            control2: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.36),
            control1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.minY + rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.maxY),
            control1: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.26),
            control2: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.54)
        )
        path.closeSubpath()
        return path
    }
}

private struct BandanaTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42))
        path.closeSubpath()
        return path
    }
}

private struct SmileShape: Shape {
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.midY)
        let end = CGPoint(x: rect.maxX, y: rect.midY)
        let control = CGPoint(x: rect.midX, y: rect.midY + rect.height * depth)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

private extension DogMetrics {
    func scaled(by factor: CGFloat) -> DogMetrics {
        DogMetrics(
            bodyWidth: bodyWidth * factor,
            bodyHeight: bodyHeight * factor,
            bodyCornerRadius: bodyCornerRadius * factor,
            headSize: headSize * factor,
            earWidth: earWidth * factor,
            earHeight: earHeight * factor,
            legHeight: legHeight * factor,
            tailLength: tailLength * factor,
            headYOffset: headYOffset * factor,
            bodyYOffset: bodyYOffset * factor
        )
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case today
    case pomodoro
    case appearance
    case reminders
    case phrases
    case favorites
    case clipboard
    case hotkeys
    case behavior
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .pomodoro: return "番茄钟"
        case .appearance: return "形象"
        case .reminders: return "提醒"
        case .phrases: return "文案"
        case .favorites: return "常用入口"
        case .clipboard: return "剪贴板"
        case .hotkeys: return "快捷键"
        case .behavior: return "行为"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .today: return "当天记录"
        case .pomodoro: return "专注节奏"
        case .appearance: return "小狗形象"
        case .reminders: return "喝水、休息和打气"
        case .phrases: return "气泡和通知"
        case .favorites: return "网址、文件和文件夹"
        case .clipboard: return "复制记录"
        case .hotkeys: return "全局操作"
        case .behavior: return "浮窗和重置"
        case .about: return "作者和支持"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .pomodoro: return "timer"
        case .appearance: return "pawprint.fill"
        case .reminders: return "bell.badge.fill"
        case .phrases: return "text.bubble.fill"
        case .favorites: return "star.fill"
        case .clipboard: return "doc.on.clipboard"
        case .hotkeys: return "keyboard"
        case .behavior: return "slider.horizontal.3"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: return Color(red: 0.24, green: 0.58, blue: 0.42)
        case .pomodoro: return PomodoroMode.focus.tint
        case .appearance: return Color(red: 0.82, green: 0.54, blue: 0.24)
        case .reminders: return Color(red: 0.30, green: 0.55, blue: 0.78)
        case .phrases: return Color(red: 0.46, green: 0.50, blue: 0.74)
        case .favorites: return Color(red: 0.76, green: 0.52, blue: 0.18)
        case .clipboard: return Color(red: 0.21, green: 0.48, blue: 0.66)
        case .hotkeys: return Color(red: 0.52, green: 0.44, blue: 0.72)
        case .behavior: return Color(red: 0.58, green: 0.54, blue: 0.45)
        case .about: return Color(red: 0.34, green: 0.48, blue: 0.58)
        }
    }
}

enum SettingsChangeScope {
    case reminderSchedule
    case hotkeys
    case statusMenu
    case all
}

struct SettingsView: View {
    @ObservedObject var store: WorkdogStore
    let nextReminderDate: (ReminderKind) -> Date?
    let onSettingsChanged: (SettingsChangeScope) -> Void
    let onOpenClipboard: () -> Void

    @State private var selectedSection: SettingsSection = .today
    @State private var presentedTodayDetailKind: ReminderKind?
    @State private var favoriteAlias = ""
    @State private var favoriteTarget = ""
    @State private var favoriteKind: FavoriteEntryKind = .link
    @State private var favoriteParentFolderID: FavoriteEntry.ID?
    @State private var editingFavoriteEntryID: FavoriteEntry.ID?
    @State private var expandedFavoriteSettingsFolderIDs: Set<FavoriteEntry.ID> = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionHeader
                    selectedContent
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 960, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.remindersEnabled) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.waterEnabled) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.restEnabled) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.cheerEnabled) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.waterIntervalMinutes) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.restIntervalMinutes) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.cheerIntervalMinutes) { _ in onSettingsChanged(.reminderSchedule) }
        .onChange(of: store.pomodoroFocusMinutes) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.pomodoroShortBreakMinutes) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.pomodoroLongBreakMinutes) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.pomodoroLongBreakEvery) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.clipboardHistoryEnabled) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.favoriteEntries) { _ in onSettingsChanged(.statusMenu) }
        .onChange(of: store.hotkeysEnabled) { _ in onSettingsChanged(.hotkeys) }
        .onChange(of: store.hotkeys) { _ in onSettingsChanged(.hotkeys) }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .today:
            todaySummary
        case .pomodoro:
            pomodoroSettings
        case .appearance:
            appearanceSettings
        case .reminders:
            reminderSettings
        case .phrases:
            phraseSettings
        case .favorites:
            favoriteSettings
        case .clipboard:
            clipboardSettings
        case .hotkeys:
            hotkeySettings
        case .behavior:
            behaviorSettings
        case .about:
            aboutSettings
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.24, green: 0.47, blue: 0.60))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Happy Workdog")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Text("设置")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarItem(for: section)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 194)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    private func sidebarItem(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? section.tint : Color.secondary)
                    .frame(width: 22, height: 22)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? section.tint.opacity(0.13) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(section.tint)
                        .frame(width: 3, height: 18)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selectedSection.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(selectedSection.tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedSection.tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.title)
                    .font(.system(size: 24, weight: .bold))

                Text(selectedSection.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedSection == .today {
                Text(store.todayDateKey)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }

    private var todayReminderTotal: Int {
        store.todayWaterReminders + store.todayRestReminders + store.todayCheerReminders
    }

    @ViewBuilder
    private var todaySummary: some View {
        if let detailKind = presentedTodayDetailKind {
            todayDetail(for: detailKind)
        } else {
            todayOverview
        }
    }

    private var todayOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                TodayMetricTile(
                    title: "喝水记录",
                    value: store.todayWaterRecords,
                    symbol: ReminderKind.water.symbol,
                    tint: ReminderKind.water.tint,
                    showsDetailArrow: true
                ) {
                    presentedTodayDetailKind = .water
                }
                TodayMetricTile(
                    title: "休息记录",
                    value: store.todayRestRecords,
                    symbol: ReminderKind.rest.symbol,
                    tint: ReminderKind.rest.tint,
                    showsDetailArrow: true
                ) {
                    presentedTodayDetailKind = .rest
                }
                TodayMetricTile(
                    title: "打气记录",
                    value: store.todayCheerRecords,
                    symbol: ReminderKind.cheer.symbol,
                    tint: ReminderKind.cheer.tint,
                    showsDetailArrow: true
                ) {
                    presentedTodayDetailKind = .cheer
                }
                TodayMetricTile(
                    title: "今日专注",
                    value: store.todayFocusCount,
                    symbol: "timer",
                    tint: PomodoroMode.focus.tint
                )
                TodayMetricTile(
                    title: "收到提醒",
                    value: todayReminderTotal,
                    symbol: "bell.badge.fill",
                    tint: Color(red: 0.52, green: 0.40, blue: 0.88)
                )
                TodayMetricTile(
                    title: "摸摸小狗",
                    value: store.todayPetTouches,
                    symbol: "hand.tap.fill",
                    tint: Color(red: 0.88, green: 0.42, blue: 0.42)
                )
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("记录日期")
                                .font(.system(size: 13, weight: .semibold))
                            Text(store.todayDateKey)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Spacer()

                        Button(role: .destructive) {
                            store.resetTodayActivity()
                        } label: {
                            Label("清空今天", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        todayBreakdownRow(
                            title: "已记录",
                            items: [
                                "喝水 \(store.todayWaterRecords)",
                                "休息 \(store.todayRestRecords)",
                                "打气 \(store.todayCheerRecords)",
                            ]
                        )
                        todayBreakdownRow(
                            title: "自动提醒",
                            items: [
                                "喝水 \(store.todayWaterReminders)",
                                "休息 \(store.todayRestReminders)",
                                "打气 \(store.todayCheerReminders)",
                            ]
                        )
                    }
                }
            }
        }
        .onAppear {
            store.refreshTodayActivityIfNeeded()
        }
    }

    private func todayDetail(for kind: ReminderKind) -> some View {
        let events = todayEvents(for: kind)

        return VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Button {
                            presentedTodayDetailKind = nil
                        } label: {
                            Label("返回今日", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Label("\(kind.title)明细", systemImage: kind.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(kind.tint)

                        Spacer()

                        Text("\(events.count) 条")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack(spacing: 10) {
                        statusPill(title: "手动 \(events.filter { $0.kind == .manualRecord }.count)", symbol: "hand.tap.fill", tint: kind.tint)
                        statusPill(title: "自动 \(events.filter { $0.kind == .automaticReminder }.count)", symbol: "bell.badge.fill", tint: kind.tint)
                    }
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text("今天还没有\(kind.title)明细。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    } else {
                        ForEach(events) { event in
                            TodayActivityEventRow(event: event)

                            if event.id != events.last?.id {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }
                }
            }
        }
    }

    private func todayEvents(for kind: ReminderKind) -> [WorkdogActivityEvent] {
        store.todayActivityEvents.filter { $0.reminder == kind }
    }

    private var pomodoroSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                HStack(alignment: .center, spacing: 18) {
                    PomodoroClockFace(store: store, size: 112, showsModeLabel: true)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            statusPill(title: store.pomodoroStateText, symbol: store.pomodoroMode.symbol, tint: store.pomodoroMode.tint)
                            statusPill(title: "累计专注 \(store.completedFocusCount)", symbol: "checkmark.circle.fill", tint: Color(red: 0.24, green: 0.58, blue: 0.42))
                        }

                        Picker("当前模式", selection: Binding(
                            get: { store.pomodoroMode },
                            set: { store.selectPomodoroMode($0) }
                        )) {
                            ForEach(PomodoroMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 330)
                    }
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    durationRow(title: "专注", value: $store.pomodoroFocusMinutes, range: 1...90, tint: PomodoroMode.focus.tint)
                    durationRow(title: "短休", value: $store.pomodoroShortBreakMinutes, range: 1...30, tint: PomodoroMode.shortBreak.tint)
                    durationRow(title: "长休", value: $store.pomodoroLongBreakMinutes, range: 5...60, tint: PomodoroMode.longBreak.tint)

                    HStack {
                        Text("长休频率")
                            .frame(width: 72, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Stepper("每 \(store.pomodoroLongBreakEvery) 个专注后长休", value: $store.pomodoroLongBreakEvery, in: 2...8)
                    }
                }
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup {
                HStack(alignment: .center, spacing: 18) {
                    DogAvatarView(
                        coat: store.coat,
                        shape: store.bodyShape,
                        mood: store.currentMood,
                        scale: store.avatarScale
                    )
                    .frame(width: 118, height: 118)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.dogName.isEmpty ? "快乐小狗" : store.dogName)
                            .font(.system(size: 20, weight: .bold))
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            statusPill(title: store.bodyShape.title, symbol: "pawprint.fill", tint: SettingsSection.appearance.tint)
                            statusPill(title: store.coat.title, symbol: "paintpalette.fill", tint: store.coat.accent)
                        }

                        Text("\(store.avatarDisplayScale, specifier: "%.2f")x")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    row("名字") {
                        TextField("快乐小狗", text: $store.dogName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                    }

                    row("体型") {
                        Picker("体型", selection: $store.bodyShape) {
                            ForEach(DogShape.allCases) { shape in
                                Text(shape.title).tag(shape)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 340)
                    }

                    row("毛色") {
                        HStack(spacing: 10) {
                            ForEach(DogCoat.allCases) { coat in
                                Button(action: { store.coat = coat }) {
                                    Circle()
                                        .fill(coat.body)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(store.coat == coat ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.75), lineWidth: 1)
                                                .padding(2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .help(coat.title)
                            }
                        }
                    }

                    row("大小") {
                        HStack(spacing: 12) {
                            Slider(value: $store.avatarScale, in: WorkdogStore.avatarScaleRange, step: 0.01)
                                .frame(maxWidth: 300)
                            Text("\(store.avatarDisplayScale, specifier: "%.2f")x")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var reminderSettings: some View {
        settingsGroup {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    Toggle("启用提醒", isOn: $store.remindersEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Picker("提醒节奏", selection: Binding(
                        get: { store.reminderPreset },
                        set: { store.applyReminderPreset($0) }
                    )) {
                        ForEach(ReminderPreset.selectableCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                        if store.reminderPreset == .custom {
                            Text(ReminderPreset.custom.title).tag(ReminderPreset.custom)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .disabled(!store.remindersEnabled)
                }

                Divider()

                reminderRow(kind: .water, isOn: $store.waterEnabled, interval: reminderIntervalBinding(for: .water), range: 1...180)
                reminderRow(kind: .rest, isOn: $store.restEnabled, interval: reminderIntervalBinding(for: .rest), range: 30...240)
                reminderRow(kind: .cheer, isOn: $store.cheerEnabled, interval: reminderIntervalBinding(for: .cheer), range: 30...300)

                Text("手动记录后会重新计算同类提醒；多条提醒靠得太近时会自动错开。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var phraseSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("小狗文案包")
                                .font(.system(size: 14, weight: .bold))
                            Text("每行一条候选文案；触发时随机选一句。支持 {name}、{count}、{completedFocusCount}。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            store.resetPhrasePackToDefaults()
                        } label: {
                            Label("恢复默认文案", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(ReminderPhraseBook.startupLine(name: store.dogName, pack: store.phrasePack))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.22))
                        .lineLimit(2)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.74))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(SettingsSection.phrases.tint.opacity(0.18), lineWidth: 1)
                                )
                        )
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    phraseEditor(
                        title: "启动",
                        subtitle: "应用启动和恢复默认文案后显示",
                        lines: phraseLinesBinding(
                            get: { $0.startup },
                            set: { $0.startup = $1 }
                        ),
                        placeholder: "{name}，我会在这里陪着你。"
                    )
                    phraseEditor(
                        title: "摸摸小狗",
                        subtitle: "点击小狗时显示",
                        lines: phraseLinesBinding(
                            get: { $0.petting },
                            set: { $0.petting = $1 }
                        ),
                        placeholder: "摸摸收到，我会乖乖陪着你。"
                    )
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text("自动提醒")
                        .font(.system(size: 14, weight: .bold))

                    phraseEditor(
                        title: "喝水提醒",
                        subtitle: "喝水计时触发时显示并同步到系统通知",
                        lines: reminderPhraseLinesBinding(for: .water, group: .reminder),
                        placeholder: "{name}，先喝两口水，脑子会更顺。"
                    )
                    phraseEditor(
                        title: "休息提醒",
                        subtitle: "休息计时触发时显示并同步到系统通知",
                        lines: reminderPhraseLinesBinding(for: .rest, group: .reminder),
                        placeholder: "站起来走两步，肩膀会感谢你。"
                    )
                    phraseEditor(
                        title: "打气提醒",
                        subtitle: "打气计时触发时显示并同步到系统通知",
                        lines: reminderPhraseLinesBinding(for: .cheer, group: .reminder),
                        placeholder: "{name}，你已经推进很多了。"
                    )
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text("手动记录")
                        .font(.system(size: 14, weight: .bold))

                    phraseEditor(
                        title: "喝水记录",
                        subtitle: "点击喝水动作后显示，可用 {count}",
                        lines: reminderPhraseLinesBinding(for: .water, group: .record),
                        placeholder: "{name}，这次喝水我记下了，今天第 {count} 次。"
                    )
                    phraseEditor(
                        title: "休息记录",
                        subtitle: "点击休息动作后显示，可用 {count}",
                        lines: reminderPhraseLinesBinding(for: .rest, group: .record),
                        placeholder: "{name}，这次休息我记下了，今天第 {count} 次。"
                    )
                    phraseEditor(
                        title: "打气记录",
                        subtitle: "点击打气动作后显示，可用 {count}",
                        lines: reminderPhraseLinesBinding(for: .cheer, group: .record),
                        placeholder: "{name}，给自己加一格能量，今天第 {count} 次。"
                    )
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text("番茄钟")
                        .font(.system(size: 14, weight: .bold))

                    phraseEditor(
                        title: "开始专注",
                        subtitle: "专注计时开始时显示",
                        lines: phraseLinesBinding(
                            get: { $0.pomodoroFocusStart },
                            set: { $0.pomodoroFocusStart = $1 }
                        ),
                        placeholder: "进入专注时间，我帮你守着节奏。"
                    )
                    phraseEditor(
                        title: "开始休息",
                        subtitle: "短休或长休计时开始时显示",
                        lines: phraseLinesBinding(
                            get: { $0.pomodoroBreakStart },
                            set: { $0.pomodoroBreakStart = $1 }
                        ),
                        placeholder: "休息时间到，先把自己放轻一点。"
                    )
                    phraseEditor(
                        title: "专注完成",
                        subtitle: "普通番茄钟完成后显示",
                        lines: pomodoroCompletionLinesBinding(\.focus),
                        placeholder: "{name}，一个番茄钟完成了，先离开屏幕几分钟。"
                    )
                    phraseEditor(
                        title: "长休节点",
                        subtitle: "每轮长休前的专注完成后显示，可用 {completedFocusCount}",
                        lines: pomodoroCompletionLinesBinding(\.focusMilestone),
                        placeholder: "{name}，第 {completedFocusCount} 个专注完成，去认真休息一会儿。"
                    )
                    phraseEditor(
                        title: "短休结束",
                        subtitle: "短休倒计时结束后显示",
                        lines: pomodoroCompletionLinesBinding(\.shortBreak),
                        placeholder: "短休结束，回来慢慢进入下一段专注。"
                    )
                    phraseEditor(
                        title: "长休结束",
                        subtitle: "长休倒计时结束后显示",
                        lines: pomodoroCompletionLinesBinding(\.longBreak),
                        placeholder: "长休结束，状态回血了，可以继续推进。"
                    )
                }
            }
        }
    }

    private var clipboardSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("记录剪贴板", isOn: $store.clipboardHistoryEnabled)
                        .toggleStyle(.switch)

                    row("最多保存") {
                        Picker("最多保存", selection: $store.clipboardMaxHistoryCount) {
                            ForEach(WorkdogStore.clipboardHistoryCountOptions, id: \.self) { count in
                                Text("\(count) 条").tag(count)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 360)
                    }

                    Divider()

                    Toggle("记录文本", isOn: $store.clipboardRecordTextEnabled)
                        .toggleStyle(.switch)
                        .disabled(!store.clipboardHistoryEnabled)

                    Toggle("记录图片", isOn: $store.clipboardRecordImageEnabled)
                        .toggleStyle(.switch)
                        .disabled(!store.clipboardHistoryEnabled)

                    Toggle("记录文件", isOn: $store.clipboardRecordFileEnabled)
                        .toggleStyle(.switch)
                        .disabled(!store.clipboardHistoryEnabled)

                    Toggle("自动过滤疑似敏感文本", isOn: $store.clipboardSensitiveFilteringEnabled)
                        .toggleStyle(.switch)
                        .disabled(!store.clipboardHistoryEnabled || !store.clipboardRecordTextEnabled)
                        .help("关闭后，文本复制记录不会再按密码或 Token 规则过滤")

                    clipboardSensitiveRuleEditor
                    clipboardSensitiveRules
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前历史")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(store.clipboardHistory.count) / \(store.clipboardMaxHistoryCount) 条，图片缓存保存在本机，文件历史只保存路径。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: onOpenClipboard) {
                            Label("打开历史", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            store.clearClipboardHistory()
                        } label: {
                            Label("清空历史", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.clipboardHistory.isEmpty)
                    }

                    if store.clipboardHistory.isEmpty {
                        Text(store.clipboardHistoryEnabled ? "暂无历史记录" : "剪贴板记录已暂停")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(store.clipboardHistory.prefix(3))) { item in
                                ClipboardHistoryPreviewRow(store: store, item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var clipboardSensitiveRuleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("敏感关键词")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(store.clipboardSensitiveKeywords.count) 个")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsSection.clipboard.tint)
                    .monospacedDigit()

                Spacer()

                Button {
                    store.clipboardSensitiveKeywordsText = WorkdogStore.defaultClipboardSensitiveKeywordsText
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextEditor(text: $store.clipboardSensitiveKeywordsText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minHeight: 78, maxHeight: 96)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
                .help("每行一个关键词，也可以用逗号或分号分隔")

            Toggle("识别大小写、数字、符号混合的短串", isOn: $store.clipboardSensitiveTokenHeuristicEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .medium))
                .help("关闭后，只按上面的关键词过滤文本")
        }
        .opacity(store.clipboardHistoryEnabled && store.clipboardRecordTextEnabled ? 1 : 0.58)
    }

    private var clipboardSensitiveRules: some View {
        let isActive = store.clipboardHistoryEnabled
            && store.clipboardRecordTextEnabled
            && store.clipboardSensitiveFilteringEnabled
        let keywords = store.clipboardSensitiveKeywords
        let keywordText = keywords.isEmpty ? "未设置关键词" : keywords.joined(separator: "、")

        return VStack(alignment: .leading, spacing: 9) {
            Label("当前过滤规则", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? SettingsSection.clipboard.tint : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                clipboardSensitiveRule("关键词匹配：JSON 字段名或非 JSON 文本包含任一关键词时过滤。当前关键词：\(keywordText)。")
                if store.clipboardSensitiveTokenHeuristicEnabled {
                    clipboardSensitiveRule("复杂短串：非 JSON 文本长度为 8 到 128 字、没有空白字符，并同时包含小写字母、大写字母、数字、符号中的至少 3 类时过滤。")
                } else {
                    clipboardSensitiveRule("复杂短串识别已关闭，只按关键词过滤。")
                }
            }

            Text(store.clipboardSensitiveFilteringEnabled ? "普通 JSON 不会因为包含括号、引号或数字被过滤；关键词为空时，仅复杂短串开关会生效。" : "当前已关闭敏感文本过滤，复制的文本只受“记录文本”开关控制。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill((isActive ? SettingsSection.clipboard.tint : Color.secondary).opacity(isActive ? 0.42 : 0.22))
                .frame(width: 3)
        }
        .opacity(store.clipboardHistoryEnabled && store.clipboardRecordTextEnabled ? 1 : 0.58)
    }

    private func clipboardSensitiveRule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(SettingsSection.clipboard.tint.opacity(0.55))
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var favoriteSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(editingFavoriteEntryID == nil ? "新增入口" : "编辑入口")
                            .font(.system(size: 14, weight: .bold))

                        Spacer()

                        if editingFavoriteEntryID != nil {
                            Button {
                                resetFavoriteForm()
                            } label: {
                                Label("取消编辑", systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Picker("类型", selection: $favoriteKind) {
                        ForEach(FavoriteEntryKind.selectableCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    row("别名") {
                        TextField(favoriteKind.isFolder ? "例如：项目、文档、工作" : "例如：后台、日报、GitHub", text: $favoriteAlias)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }

                    if !favoriteKind.isFolder {
                        row("地址") {
                            TextField("网址或本地路径", text: $favoriteTarget)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 480)
                        }
                    }

                    row("父文件夹") {
                        Picker("父文件夹", selection: $favoriteParentFolderID) {
                            Text("根目录").tag(Optional<FavoriteEntry.ID>.none)
                            ForEach(availableFavoriteParentFolders) { folder in
                                Text(folder.alias).tag(Optional(folder.id))
                            }
                        }
                        .frame(maxWidth: 260)
                    }

                    HStack {
                        Button {
                            saveFavoriteForm()
                        } label: {
                            Label(editingFavoriteEntryID == nil ? "添加入口" : "保存修改", systemImage: editingFavoriteEntryID == nil ? "plus" : "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSaveFavoriteForm)

                        Text("文件夹下面可以继续添加链接或子文件夹。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("入口列表")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(store.favoriteEntries.count) 个节点，可在小狗浮窗“更多”里打开。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if store.favoriteEntries.isEmpty {
                        Text("还没有常用入口。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(store.favoriteRootNodes) { node in
                                FavoriteSettingsTreeNode(
                                    node: node,
                                    expandedFolderIDs: $expandedFavoriteSettingsFolderIDs,
                                    onEdit: editFavoriteEntry,
                                    onDelete: store.removeFavoriteEntry
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var hotkeySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("启用全局快捷键", isOn: $store.hotkeysEnabled)
                        .toggleStyle(.switch)

                    Divider()

                    VStack(spacing: 10) {
                        ForEach(HotkeyAction.allCases) { action in
                            HotkeySettingRow(
                                store: store,
                                action: action,
                                isEnabled: store.hotkeysEnabled,
                                hasRegistrationFailed: store.failedHotkeyActions.contains(action)
                            )
                        }
                    }
                }
            }

            settingsGroup {
                HStack {
                    Text("录入快捷键时，请按下包含 ⌘、⌥ 或 ⌃ 的组合键。Delete 可清空，ESC 取消。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        store.resetHotkeysToDefaults()
                        onSettingsChanged(.hotkeys)
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var behaviorSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("提醒时把小狗拉到前面", isOn: $store.revealWindowOnReminder)
                        .toggleStyle(.switch)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("浮窗常驻按钮")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("更多固定显示，最多置顶 \(QuickAction.maximumPinnedCount) 个动作。")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                store.resetPinnedQuickActions()
                            } label: {
                                Label("恢复默认", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            FixedQuickActionBadge(
                                title: "更多",
                                symbol: "ellipsis",
                                tint: Color(red: 0.44, green: 0.38, blue: 0.62)
                            )
                            ForEach(Array(store.pinnedQuickActions.enumerated()), id: \.element) { index, action in
                                PinnedQuickActionOrderRow(store: store, action: action, index: index)
                            }
                        }

                        if store.pinnedQuickActions.count < QuickAction.maximumPinnedCount {
                            Divider()

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], alignment: .leading, spacing: 10) {
                                ForEach(QuickAction.allCases.filter { !store.isQuickActionPinned($0) }) { action in
                                    AvailableQuickActionRow(store: store, action: action)
                                }
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            store.resetPomodoroStats()
                        } label: {
                            Label("清空番茄钟统计", systemImage: "chart.bar.xaxis")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            store.resetToDefaults()
                            onSettingsChanged(.all)
                        } label: {
                            Label("恢复默认", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                HStack(alignment: .center, spacing: 18) {
                    DogAvatarView(
                        coat: store.coat,
                        shape: store.bodyShape,
                        mood: .happy,
                        scale: WorkdogStore.defaultAvatarScale
                    )
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Happy Workdog")
                            .font(.system(size: 24, weight: .bold))
                        Text("一个陪你专注、提醒喝水休息、顺手管理剪贴板和常用入口的 macOS 桌面小狗。")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            statusPill(title: "版本 0.1.1", symbol: "tag.fill", tint: SettingsSection.about.tint)
                            statusPill(title: "SwiftUI + AppKit", symbol: "hammer.fill", tint: Color(red: 0.38, green: 0.56, blue: 0.42))
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    Text("关于作者")
                        .font(.system(size: 14, weight: .bold))

                    HStack(alignment: .center, spacing: 16) {
                        AuthorAvatarImage()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("罗码视界")
                                .font(.system(size: 16, weight: .bold))
                            Text("快乐小狗的作者，全网同名罗码视界。持续打磨这个本地优先的小工具，让它更顺手、更少打扰。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link(destination: URL(string: "https://github.com/LeroyPine/happy-workdog")!) {
                                Label("github.com/LeroyPine/happy-workdog", systemImage: "link")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(SettingsSection.about.tint)
                            .padding(.top, 4)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color(red: 0.66, green: 0.42, blue: 0.24))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(red: 0.66, green: 0.42, blue: 0.24).opacity(0.12))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("请作者喝杯咖啡")
                                .font(.system(size: 14, weight: .bold))
                            Text("左侧支付宝，右侧微信。喜欢这个小狗的话，感谢支持作者继续补功能。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Button {
                            copyAuthorCoffeeText()
                        } label: {
                            Label("复制支持文案", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    DonateCoffeeImage()
                        .frame(maxWidth: 760)
                }
            }
        }
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.075), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.025), radius: 4, x: 0, y: 1)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 82, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }

    private func statusPill(title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func durationRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 82, alignment: .leading)
                .foregroundStyle(.secondary)

            Slider(value: value, in: range, step: 1)
                .tint(tint)
                .frame(width: 310)

            Text("\(Int(value.wrappedValue)) 分钟")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .frame(minHeight: 34)
    }

    private func reminderIntervalBinding(for kind: ReminderKind) -> Binding<Double> {
        Binding(
            get: {
                switch kind {
                case .water:
                    return store.waterIntervalMinutes
                case .rest:
                    return store.restIntervalMinutes
                case .cheer:
                    return store.cheerIntervalMinutes
                }
            },
            set: { store.setReminderInterval(kind, minutes: $0) }
        )
    }

    private enum PhraseLineGroup {
        case reminder
        case record
    }

    private func phraseLinesBinding(
        get: @escaping (WorkdogPhrasePack) -> [String],
        set: @escaping (inout WorkdogPhrasePack, [String]) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                get(store.phrasePack).joined(separator: "\n")
            },
            set: { rawText in
                var pack = store.phrasePack
                set(&pack, WorkdogPhrasePack.editableLines(from: rawText))
                store.phrasePack = pack
            }
        )
    }

    private func reminderPhraseLinesBinding(for kind: ReminderKind, group: PhraseLineGroup) -> Binding<String> {
        phraseLinesBinding(
            get: { pack in
                switch group {
                case .reminder:
                    return pack.reminders.lines(for: kind)
                case .record:
                    return pack.records.lines(for: kind)
                }
            },
            set: { pack, lines in
                switch group {
                case .reminder:
                    pack.reminders.setLines(lines, for: kind)
                case .record:
                    pack.records.setLines(lines, for: kind)
                }
            }
        )
    }

    private func pomodoroCompletionLinesBinding(_ keyPath: WritableKeyPath<PomodoroCompletionPhraseLines, [String]>) -> Binding<String> {
        phraseLinesBinding(
            get: { $0.pomodoroCompletion[keyPath: keyPath] },
            set: { pack, lines in
                pack.pomodoroCompletion[keyPath: keyPath] = lines
            }
        )
    }

    private func phraseEditor(title: String, subtitle: String, lines: Binding<String>, placeholder: String) -> some View {
        PhraseEditorView(
            title: title,
            subtitle: subtitle,
            placeholder: placeholder,
            committedText: lines
        )
    }

    private func copyAuthorCoffeeText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Happy Workdog 很好用，给作者罗码视界整杯咖啡，继续加油。", forType: .string)
        store.showStatusMessage("支持文案已经复制，谢谢你请作者喝咖啡。", mood: .happy)
    }

    private var canSaveFavoriteForm: Bool {
        guard !favoriteAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return favoriteKind.isFolder || !favoriteTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableFavoriteParentFolders: [FavoriteEntry] {
        guard let editingFavoriteEntryID else { return store.favoriteFolders }
        let descendants = favoriteDescendantIDs(in: store.favoriteRootNodes, of: editingFavoriteEntryID)
        return store.favoriteFolders.filter { folder in
            folder.id != editingFavoriteEntryID && !descendants.contains(folder.id)
        }
    }

    private func saveFavoriteForm() {
        guard canSaveFavoriteForm else { return }
        if let editingFavoriteEntryID,
           let current = store.favoriteEntries.first(where: { $0.id == editingFavoriteEntryID }) {
            var updated = current
            updated.alias = favoriteAlias
            updated.target = favoriteKind.isFolder ? "" : favoriteTarget
            updated.kind = favoriteKind
            updated.parentFolderID = favoriteParentFolderID
            store.updateFavoriteEntry(updated)
        } else {
            store.addFavoriteEntry(
                alias: favoriteAlias,
                target: favoriteKind.isFolder ? "" : favoriteTarget,
                kind: favoriteKind,
                parentFolderID: favoriteParentFolderID
            )
        }
        resetFavoriteForm()
    }

    private func editFavoriteEntry(_ entry: FavoriteEntry) {
        editingFavoriteEntryID = entry.id
        favoriteAlias = entry.alias
        favoriteTarget = entry.target
        favoriteKind = entry.kind
        favoriteParentFolderID = entry.parentFolderID
    }

    private func resetFavoriteForm() {
        editingFavoriteEntryID = nil
        favoriteAlias = ""
        favoriteTarget = ""
        favoriteKind = .link
        favoriteParentFolderID = nil
    }

    private func favoriteDescendantIDs(in nodes: [FavoriteTreeNode], of folderID: FavoriteEntry.ID) -> Set<FavoriteEntry.ID> {
        for node in nodes {
            if node.id == folderID {
                return favoriteFlattenedIDs(in: node.children)
            }
            let descendants = favoriteDescendantIDs(in: node.children, of: folderID)
            if !descendants.isEmpty {
                return descendants
            }
        }
        return []
    }

    private func favoriteFlattenedIDs(in nodes: [FavoriteTreeNode]) -> Set<FavoriteEntry.ID> {
        nodes.reduce(into: Set<FavoriteEntry.ID>()) { result, node in
            result.insert(node.id)
            result.formUnion(favoriteFlattenedIDs(in: node.children))
        }
    }

    private func nextReminderText(for kind: ReminderKind, isOn: Bool) -> String {
        _ = store.reminderScheduleRevision
        guard store.remindersEnabled, isOn else { return "已暂停" }
        guard let date = nextReminderDate(kind) else { return "等待排期" }
        let remaining = max(0, date.timeIntervalSinceNow)
        if remaining < 60 {
            return "约 1 分钟内"
        }
        if remaining < 60 * 60 {
            return "约 \(Int(ceil(remaining / 60))) 分钟后"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "约 \(formatter.string(from: date))"
    }

    private func reminderRow(kind: ReminderKind, isOn: Binding<Bool>, interval: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: isOn) {
                    Label {
                        Text(kind.title)
                            .font(.system(size: 13, weight: .semibold))
                    } icon: {
                        Image(systemName: kind.symbol)
                            .foregroundStyle(kind.tint)
                    }
                }
                .toggleStyle(.switch)

                Spacer()

                Text(nextReminderText(for: kind, isOn: isOn.wrappedValue))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .trailing)

                Text("\(Int(interval.wrappedValue)) 分钟")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 86, alignment: .trailing)
            }

            Slider(value: interval, in: range, step: 5)
                .tint(kind.tint)
                .disabled(!store.remindersEnabled || !isOn.wrappedValue)
        }
        .padding(.vertical, 2)
        .opacity(store.remindersEnabled && isOn.wrappedValue ? 1 : 0.58)
    }

    private func todayBreakdownRow(title: String, items: [String]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PhraseEditorView: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var committedText: String

    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    private var lineCount: Int {
        WorkdogPhrasePack.editableLines(from: draftText).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(lineCount) 条")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draftText)
                    .font(.system(size: 12, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(4)
                    .frame(minHeight: 74)
                    .background(Color.clear)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isFocused ? SettingsSection.phrases.tint.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            draftText = committedText
        }
        .onChange(of: draftText) { newValue in
            committedText = WorkdogPhrasePack.editableLines(from: newValue).joined(separator: "\n")
        }
        .onChange(of: committedText) { newValue in
            let normalizedDraftText = WorkdogPhrasePack.editableLines(from: draftText).joined(separator: "\n")
            guard newValue != draftText, newValue != normalizedDraftText else { return }
            draftText = newValue
        }
    }
}

private struct DonateCoffeeImage: View {
    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: "donate-coffee", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 18, weight: .semibold))
                    Text("赞赏图暂时没有加载出来")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color.primary.opacity(0.04))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct AuthorAvatarImage: View {
    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: "author-avatar", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(SettingsSection.about.tint)
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(SettingsSection.about.tint.opacity(0.12))
                    )
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(SettingsSection.about.tint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        .accessibilityLabel("罗码视界头像")
    }
}

private struct PinnedQuickActionOrderRow: View {
    @ObservedObject var store: WorkdogStore
    let action: QuickAction
    let index: Int

    private var canMoveUp: Bool {
        index > 0
    }

    private var canMoveDown: Bool {
        index < store.pinnedQuickActions.count - 1
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )

            Label {
                Text(action.title)
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: action.symbol)
                    .foregroundStyle(action.tint)
            }

            Spacer(minLength: 0)

            Button {
                store.movePinnedQuickAction(action, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help("上移")

            Button {
                store.movePinnedQuickAction(action, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help("下移")

            Button(role: .destructive) {
                store.setQuickAction(action, pinned: false)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("移除")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
        .help("当前第 \(index + 1) 个常驻按钮")
    }
}

private struct AvailableQuickActionRow: View {
    @ObservedObject var store: WorkdogStore
    let action: QuickAction

    var body: some View {
        Button {
            store.setQuickAction(action, pinned: true)
        } label: {
            Label {
                Text(action.title)
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: action.symbol)
                    .foregroundStyle(action.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help("添加到常驻按钮")
    }
}

private struct FixedQuickActionBadge: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text("固定")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
        .help("\(title)固定显示")
    }
}

private struct FavoriteSettingsTreeNode: View {
    let node: FavoriteTreeNode
    @Binding var expandedFolderIDs: Set<FavoriteEntry.ID>
    let onEdit: (FavoriteEntry) -> Void
    let onDelete: (FavoriteEntry) -> Void

    private var isExpanded: Bool {
        expandedFolderIDs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FavoriteSettingsRow(
                entry: node.entry,
                isExpanded: isExpanded,
                childCount: node.children.count,
                onToggle: toggleIfFolder,
                onEdit: onEdit,
                onDelete: onDelete
            )

            if node.entry.isFolder && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children) { child in
                        FavoriteSettingsTreeNode(
                            node: child,
                            expandedFolderIDs: $expandedFolderIDs,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    private func toggleIfFolder() {
        guard node.entry.isFolder else { return }
        if expandedFolderIDs.contains(node.id) {
            expandedFolderIDs.remove(node.id)
        } else {
            expandedFolderIDs.insert(node.id)
        }
    }
}

private struct FavoriteSettingsRow: View {
    let entry: FavoriteEntry
    let isExpanded: Bool
    let childCount: Int
    let onToggle: () -> Void
    let onEdit: (FavoriteEntry) -> Void
    let onDelete: (FavoriteEntry) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if entry.isFolder {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else {
                Color.clear
                    .frame(width: 18, height: 24)
            }

            Image(systemName: entry.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsSection.favorites.tint)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(SettingsSection.favorites.tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.alias)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if entry.isFolder {
                    Text("\(childCount) 个子项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.displayTarget)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Button {
                onEdit(entry)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("编辑")

            Button(role: .destructive) {
                onDelete(entry)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("删除")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

private struct TodayMetricTile: View {
    let title: String
    let value: Int
    let symbol: String
    let tint: Color
    var showsDetailArrow = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    tileContent
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(tint)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.13))
                    )

                Spacer()

                if showsDetailArrow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(tint.opacity(0.10))
                        )
                }
            }

            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private struct TodayActivityEventRow: View {
    let event: WorkdogActivityEvent

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: event.happenedAt)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.kind == .manualRecord ? "hand.tap.fill" : "bell.badge.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.reminder.tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(event.reminder.tint.opacity(0.12))
                )

            Text(event.kind.title)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(timeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}

private struct ClipboardHistoryPreviewRow: View {
    @ObservedObject var store: WorkdogStore
    let item: ClipboardHistoryItem

    private let tint = Color(red: 0.18, green: 0.48, blue: 0.72)

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                )

            contentPreview

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.detailText)
                Text(item.copiedAtText)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var leadingSymbol: String {
        switch item.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            } else {
                Text("图片缓存不可用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .file:
            filePreview
        }
    }

    private var filePreview: some View {
        HStack(spacing: 10) {
            Image(nsImage: fileIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.fileCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileIcon: NSImage {
        guard let path = item.filePaths?.first else {
            return NSWorkspace.shared.icon(for: .data)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

private struct HotkeySettingRow: View {
    @ObservedObject var store: WorkdogStore
    let action: HotkeyAction
    let isEnabled: Bool
    let hasRegistrationFailed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.accentColor)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                    if hasRegistrationFailed {
                        Label("注册失败", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(action.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HotkeyRecorderButton(
                hotkey: store.hotkey(for: action),
                isEnabled: isEnabled,
                onChange: { hotkey in
                    store.setHotkey(hotkey, for: action)
                }
            )
            .frame(width: 148)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
        .opacity(isEnabled ? 1 : 0.56)
    }
}

private struct HotkeyRecorderButton: NSViewRepresentable {
    let hotkey: WorkdogHotkey?
    let isEnabled: Bool
    let onChange: (WorkdogHotkey?) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSButton {
        let button = HotkeyRecorderNSButton()
        button.onChange = onChange
        return button
    }

    func updateNSView(_ button: HotkeyRecorderNSButton, context: Context) {
        button.hotkey = hotkey
        button.onChange = onChange
        button.isEnabled = isEnabled
        button.updateTitle()
    }
}

private final class HotkeyRecorderNSButton: NSButton {
    var hotkey: WorkdogHotkey?
    var onChange: ((WorkdogHotkey?) -> Void)?

    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        focusRingType = .none
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard isEnabled else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            hotkey = nil
            isRecording = false
            onChange?(nil)
            updateTitle()
            return
        }

        if let newHotkey = WorkdogHotkey(event: event) {
            hotkey = newHotkey
            isRecording = false
            onChange?(newHotkey)
            updateTitle()
        } else {
            NSSound.beep()
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    func updateTitle() {
        if isRecording {
            title = "按下快捷键..."
        } else if let hotkey {
            title = hotkey.displayText
        } else {
            title = "未设置"
        }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: WorkdogStore
    let onSelect: (ClipboardHistoryItem) -> Void
    let onStateChanged: () -> Void

    @State private var copiedItemID: ClipboardHistoryItem.ID?
    @State private var searchText = ""

    private let tint = Color(red: 0.18, green: 0.48, blue: 0.72)
    private let imageTint = Color(red: 0.24, green: 0.58, blue: 0.42)
    private let fileTint = Color(red: 0.76, green: 0.52, blue: 0.18)

    private var textCount: Int {
        store.clipboardHistory.filter { $0.kind == .text }.count
    }

    private var imageCount: Int {
        store.clipboardHistory.filter { $0.kind == .image }.count
    }

    private var fileCount: Int {
        store.clipboardHistory.filter { $0.kind == .file }.count
    }

    private var pinnedCount: Int {
        store.clipboardHistory.filter(\.isPinned).count
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var filteredHistory: [ClipboardHistoryItem] {
        store.clipboardHistory.filter { $0.matchesSearchQuery(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            if store.clipboardHistory.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredHistory.isEmpty {
                noSearchResultsState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredHistory) { item in
                            ClipboardHistoryRow(
                                store: store,
                                item: item,
                                isCopied: copiedItemID == item.id,
                                onStateChanged: onStateChanged,
                                onSelect: {
                                    copy(item)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(tint.opacity(0.045))
                        .frame(height: 240)
                }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.13))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("剪贴板历史")
                        .font(.system(size: 22, weight: .bold))
                    Text(store.clipboardHistoryEnabled ? "最近复制的内容会保存在本机" : "记录已暂停，历史仍可取回")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(store.clipboardHistory.count)/\(store.clipboardMaxHistoryCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.11))
                    )
                    .help("当前历史数量 / 最多保存数量")

                Button(role: .destructive) {
                    store.clearClipboardHistory()
                    onStateChanged()
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.clipboardHistory.isEmpty)
                .help("清空全部剪贴板历史")
            }

            HStack(spacing: 10) {
                clipboardMetric(title: "文本", value: textCount, symbol: "doc.text", tint: tint)
                clipboardMetric(title: "图片", value: imageCount, symbol: "photo", tint: imageTint)
                clipboardMetric(title: "文件", value: fileCount, symbol: "doc", tint: fileTint)
                clipboardMetric(title: "置顶", value: pinnedCount, symbol: "pin.fill", tint: fileTint)

                Spacer(minLength: 0)

                Toggle("记录剪贴板", isOn: Binding(
                    get: { store.clipboardHistoryEnabled },
                    set: { newValue in
                        store.clipboardHistoryEnabled = newValue
                        onStateChanged()
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .semibold))
            }

            searchField
        }
        .padding(18)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.11),
                            Color(nsColor: .windowBackgroundColor).opacity(0.82),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSearching ? tint : .secondary)

            TextField("搜索文本、文件名、类型或尺寸", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))

            if isSearching {
                Text("\(filteredHistory.count) 个结果")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)

                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSearching ? tint.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func clipboardMetric(title: String, value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.clipboardHistoryEnabled ? "doc.on.clipboard" : "pause.circle")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            Text(store.clipboardHistoryEnabled ? "还没有剪贴板记录" : "剪贴板记录已暂停")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text(store.clipboardHistoryEnabled ? "复制文本、图片或文件后，它会出现在这里。" : "打开记录后，会继续保存新的文本、图片和文件。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(32)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            Text("没有找到匹配记录")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text("当前搜索：\(trimmedSearchText)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                searchText = ""
            } label: {
                Label("清空搜索", systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(32)
    }

    private func copy(_ item: ClipboardHistoryItem) {
        onSelect(item)
        copiedItemID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    @ObservedObject var store: WorkdogStore
    let item: ClipboardHistoryItem
    let isCopied: Bool
    let onStateChanged: () -> Void
    let onSelect: () -> Void

    private let tint = Color(red: 0.18, green: 0.48, blue: 0.72)
    private let successTint = Color(red: 0.24, green: 0.58, blue: 0.42)
    private let pinTint = Color(red: 0.76, green: 0.52, blue: 0.18)
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            rowHeader

            contentPreview
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(rowStrokeColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.035), radius: isHovered ? 7 : 3, x: 0, y: isHovered ? 3 : 1)
        )
        .onHover { isHovered = $0 }
        .help("点击内容复制到剪贴板")
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isCopied ? successTint : rowTint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((isCopied ? successTint : rowTint).opacity(0.13))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(kindTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(pinTint)
                            .help("已置顶")
                    }
                }

                HStack(spacing: 8) {
                    Label(item.copiedAtText, systemImage: "clock")
                    Text(item.detailText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    if store.toggleClipboardHistoryItemPinned(id: item.id) {
                        onStateChanged()
                    }
                }
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isPinned ? pinTint : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((item.isPinned ? pinTint : Color.primary).opacity(item.isPinned ? 0.13 : 0.055))
            )
            .help(item.isPinned ? "取消置顶" : "置顶这条历史")

            Button(action: onSelect) {
                Label(isCopied ? "已复制" : "回写", systemImage: isCopied ? "checkmark" : "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCopied ? successTint : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((isCopied ? successTint : Color.primary).opacity(isCopied ? 0.12 : 0.055))
            )
            .help("复制到剪贴板")

            Button(role: .destructive) {
                store.removeClipboardHistoryItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("删除这条历史")
        }
    }

    private var rowTint: Color {
        switch item.kind {
        case .text: return tint
        case .image: return Color(red: 0.24, green: 0.58, blue: 0.42)
        case .file: return Color(red: 0.76, green: 0.52, blue: 0.18)
        }
    }

    private var rowFillColor: Color {
        if isCopied {
            return successTint.opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.86 : 0.68)
    }

    private var rowStrokeColor: Color {
        if isCopied {
            return successTint.opacity(0.36)
        }
        if item.isPinned {
            return pinTint.opacity(isHovered ? 0.38 : 0.26)
        }
        return rowTint.opacity(isHovered ? 0.25 : 0.12)
    }

    private var kindTitle: String {
        switch item.kind {
        case .text: return "文本片段"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    private var leadingSymbol: String {
        if isCopied { return "checkmark.circle.fill" }
        switch item.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
                        )
                )
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 160, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.045))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(rowTint.opacity(0.18), lineWidth: 1)
                    )
            } else {
                missingContent(title: "图片文件已丢失", symbol: "photo")
            }
        case .file:
            filePreview
        }
    }

    private var filePreview: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: fileIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(rowTint.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                Text(item.fileCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(rowTint.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func missingContent(title: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var fileIcon: NSImage {
        guard let path = item.filePaths?.first else {
            return NSWorkspace.shared.icon(for: .data)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
