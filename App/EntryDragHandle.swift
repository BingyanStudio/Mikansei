import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Hosts a card at its natural size and attaches the native drag interaction to
/// the entire card bounds. UIKit's drag session supplies the real lift/drop
/// lifecycle, while the hosted SwiftUI content keeps its normal child controls.
struct EntryCardDragSource<Content: View>: UIViewRepresentable {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let entry: Entry
    private let isEnabled: Bool
    private let isPlaceholder: Bool
    private let onSessionChange: ((Bool) -> Void)?
    private let content: Content
    @Binding private var isDragging: Bool
    @Binding private var measuredContentSize: CGSize?

    init(
        entry: Entry,
        isEnabled: Bool = true,
        isDragging: Binding<Bool> = .constant(false),
        isPlaceholder: Bool = false,
        onSessionChange: ((Bool) -> Void)? = nil,
        measuredContentSize: Binding<CGSize?> = .constant(nil),
        @ViewBuilder content: () -> Content
    ) {
        self.entry = entry
        self.isEnabled = isEnabled
        self.isPlaceholder = isPlaceholder
        self.onSessionChange = onSessionChange
        self.content = content()
        self._isDragging = isDragging
        self._measuredContentSize = measuredContentSize
    }

    private var hostedContent: EntryCardHostedContent<Content> {
        EntryCardHostedContent(
            entryID: entry.id,
            content: content,
            store: store,
            environment: EntryCardHostedEnvironment(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                locale: locale,
                layoutDirection: layoutDirection,
                reduceMotion: reduceMotion,
                calendar: calendar,
                timeZone: timeZone,
                displayScale: displayScale,
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            ),
            onSizeChange: { _ in }
        )
    }

    func makeUIView(context: Context) -> EntryCardDragContainerView<Content> {
        let view = EntryCardDragContainerView(entry: entry, store: store, rootView: hostedContent, isEnabled: isEnabled, reduceMotion: reduceMotion)
        view.alpha = isPlaceholder ? 0.001 : 1
        updateCallbacks(on: view)
        view.updateRootView(makeHostedContent(on: view))
        return view
    }

    func updateUIView(_ view: EntryCardDragContainerView<Content>, context: Context) {
        view.entry = entry
        view.store = store
        view.reduceMotion = reduceMotion
        view.setDragEnabled(isEnabled && !store.readOnly)
        view.alpha = isPlaceholder ? 0.001 : 1
        updateCallbacks(on: view)
        view.updateRootView(makeHostedContent(on: view))
    }

    static func dismantleUIView(_ uiView: EntryCardDragContainerView<Content>, coordinator: ()) {
        uiView.prepareForRemoval()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EntryCardDragContainerView<Content>, context: Context) -> CGSize? {
        let proposedWidth = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let currentWidth = uiView.bounds.width.isFinite && uiView.bounds.width > 0 ? uiView.bounds.width : nil
        guard let width = proposedWidth ?? currentWidth else { return nil }
        return uiView.fittingSize(forWidth: width)
    }

    private func makeHostedContent(on view: EntryCardDragContainerView<Content>) -> EntryCardHostedContent<Content> {
        EntryCardHostedContent(
            entryID: entry.id,
            content: content,
            store: store,
            environment: EntryCardHostedEnvironment(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                locale: locale,
                layoutDirection: layoutDirection,
                reduceMotion: reduceMotion,
                calendar: calendar,
                timeZone: timeZone,
                displayScale: displayScale,
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            ),
            onSizeChange: { [weak view] size in view?.reportHostedContentSize(size) }
        )
    }

    private func updateCallbacks(on view: EntryCardDragContainerView<Content>) {
        let dragging = _isDragging
        let sizeBinding = _measuredContentSize
        let sessionChange = onSessionChange
        view.onDragSessionChange = { active in
            if dragging.wrappedValue != active { dragging.wrappedValue = active }
            sessionChange?(active)
        }
        view.onHostedContentSizeChange = { size in
            DispatchQueue.main.async { [weak view] in
                guard view != nil else { return }
                guard let oldSize = sizeBinding.wrappedValue else {
                    sizeBinding.wrappedValue = size
                    return
                }
                guard abs(oldSize.width - size.width) > 0.5 || abs(oldSize.height - size.height) > 0.5 else { return }
                sizeBinding.wrappedValue = size
            }
        }
    }
}

fileprivate struct EntryCardHostedEnvironment {
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let locale: Locale
    let layoutDirection: LayoutDirection
    let reduceMotion: Bool
    let calendar: Calendar
    let timeZone: TimeZone
    let displayScale: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
}

fileprivate struct EntryCardHostedSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}

fileprivate struct EntryCardHostedContent<Content: View>: View {
    let entryID: UUID
    let content: Content
    let store: EntryStore
    let environment: EntryCardHostedEnvironment
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: EntryCardHostedSizeKey.self, value: geometry.size)
                }
            }
            .onPreferenceChange(EntryCardHostedSizeKey.self, perform: onSizeChange)
            .environmentObject(store)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.calendar, environment.calendar)
            .environment(\.timeZone, environment.timeZone)
            .environment(\.displayScale, environment.displayScale)
            .environment(\.horizontalSizeClass, environment.horizontalSizeClass)
            .environment(\.verticalSizeClass, environment.verticalSizeClass)
            .id(entryID)
    }
}

private final class EntryCardDragDisplayLinkTarget: NSObject {
    var onTick: ((CADisplayLink) -> Void)?
    @objc func tick(_ link: CADisplayLink) { onTick?(link) }
}

final class EntryCardDragContainerView<Content: View>: UIView, UIDragInteractionDelegate {
    var entry: Entry
    var store: EntryStore
    var reduceMotion: Bool
    var onDragSessionChange: ((Bool) -> Void)?
    var onHostedContentSizeChange: ((CGSize) -> Void)?

    private let hostingController: UIHostingController<EntryCardHostedContent<Content>>
    private var dragInteraction: UIDragInteraction?
    private var canDrag = false
    private var lastHostedContentSize = CGSize.zero
    private weak var activeSession: UIDragSession?
    private weak var activeScrollView: UIScrollView?
    private var edgeScrollLink: CADisplayLink?
    private var displayLinkTarget: EntryCardDragDisplayLinkTarget?
    private var dragSessionActive = false
    private var hasReportedWillEnd = false

    fileprivate init(entry: Entry, store: EntryStore, rootView: EntryCardHostedContent<Content>, isEnabled: Bool, reduceMotion: Bool) {
        self.entry = entry
        self.store = store
        self.reduceMotion = reduceMotion
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        hostingController.safeAreaRegions = []
        hostingController.sizingOptions = [.intrinsicContentSize]
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.isOpaque = false
        hostingController.view.clipsToBounds = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setDragEnabled(isEnabled && !store.readOnly)
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        guard bounds.width.isFinite, bounds.width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        let size = fittingSize(forWidth: bounds.width)
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostingController.view.frame = bounds
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil { detachHostingController() } else { attachHostingControllerIfPossible() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { attachHostingControllerIfPossible() }
    }

    fileprivate func updateRootView(_ rootView: EntryCardHostedContent<Content>) {
        hostingController.rootView = rootView
        hostingController.view.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    fileprivate func fittingSize(forWidth width: CGFloat) -> CGSize {
        let measured = hostingController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(0, measured.height))
    }

    fileprivate func reportHostedContentSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              abs(lastHostedContentSize.width - size.width) > 0.5 || abs(lastHostedContentSize.height - size.height) > 0.5 else { return }
        lastHostedContentSize = size
        hostingController.view.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onHostedContentSizeChange?(size)
    }

    fileprivate func setDragEnabled(_ enabled: Bool) {
        canDrag = enabled
        guard enabled, dragInteraction == nil else {
            if !enabled, let dragInteraction {
                dragInteraction.isEnabled = false
                removeInteraction(dragInteraction)
                self.dragInteraction = nil
            }
            return
        }
        let interaction = UIDragInteraction(delegate: self)
        interaction.isEnabled = true
        addInteraction(interaction)
        dragInteraction = interaction
    }

    private func attachHostingControllerIfPossible() {
        guard let parent = nearestViewController else { return }
        guard hostingController.parent !== parent else { return }
        if hostingController.parent != nil {
            hostingController.willMove(toParent: nil)
            hostingController.removeFromParent()
        }
        parent.addChild(hostingController)
        if hostingController.view.superview !== self { addSubview(hostingController.view) }
        hostingController.didMove(toParent: parent)
    }

    private func detachHostingController() {
        guard hostingController.parent != nil else { return }
        hostingController.willMove(toParent: nil)
        hostingController.removeFromParent()
    }

    private var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController { return viewController }
            responder = current.next
        }
        return nil
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard canDrag, !store.readOnly,
              !touchStartedInTextSelectionArea(at: session.location(in: self)),
              let data = try? JSONEncoder().encode(entry) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return [UIDragItem(itemProvider: provider)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        let cardPath = UIBezierPath(roundedRect: bounds, cornerRadius: 18)
        parameters.visiblePath = cardPath
        parameters.shadowPath = cardPath
        let scale = reduceMotion ? CGAffineTransform.identity : CGAffineTransform(scaleX: 1.02, y: 1.02)
        let target = UIPreviewTarget(container: self, center: CGPoint(x: bounds.midX, y: bounds.midY), transform: scale)
        return UITargetedDragPreview(view: self, parameters: parameters, target: target)
    }

    func dragInteraction(_ interaction: UIDragInteraction, prefersFullSizePreviewsFor session: UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        dragSessionActive = true
        hasReportedWillEnd = false
        activeSession = session
        activeScrollView = nearestScrollView
        onDragSessionChange?(true)
        guard activeScrollView != nil else { return }

        let target = EntryCardDragDisplayLinkTarget()
        target.onTick = { [weak self] link in self?.scrollAtEdges(link) }
        let link = CADisplayLink(target: target, selector: #selector(EntryCardDragDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLinkTarget = target
        edgeScrollLink = link
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, willEndWith operation: UIDropOperation) {
        hasReportedWillEnd = true
        if operation == .copy || operation == .move {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.85)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
        }
        stopEdgeScrolling()
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        stopEdgeScrolling()
        if dragSessionActive {
            dragSessionActive = false
            onDragSessionChange?(false)
        }
    }

    fileprivate func prepareForRemoval() {
        let sessionWasActive = dragSessionActive
        stopEdgeScrolling()
        if sessionWasActive {
            if !hasReportedWillEnd { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8) }
            dragSessionActive = false
            onDragSessionChange?(false)
        }
        if let dragInteraction {
            dragInteraction.isEnabled = false
            removeInteraction(dragInteraction)
            self.dragInteraction = nil
        }
        detachHostingController()
    }

    private var nearestScrollView: UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView { return scrollView }
            candidate = view.superview
        }
        return nil
    }

    private func touchStartedInTextSelectionArea(at point: CGPoint) -> Bool {
        var candidate = hitTest(point, with: nil)
        while let view = candidate {
            if view is UITextField || view is UITextView { return true }
            if view === self { break }
            candidate = view.superview
        }
        return false
    }

    private func scrollAtEdges(_ link: CADisplayLink) {
        guard activeSession != nil, let scrollView = activeScrollView else {
            stopEdgeScrolling()
            return
        }
        let location = activeSession!.location(in: scrollView)
        let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
        let edgeDistance: CGFloat = 72
        let elapsed = link.targetTimestamp > link.timestamp ? link.targetTimestamp - link.timestamp : link.duration
        let frameStep = CGFloat(min(max(elapsed, 1.0 / 240.0), 1.0 / 15.0))
        let edgeSpeedPerSecond: CGFloat = 18 * 60
        let minimumSpeedPerSecond: CGFloat = 2 * 60
        var delta: CGFloat = 0

        if location.x >= scrollView.bounds.minX && location.x <= scrollView.bounds.maxX {
            if location.y < visibleTop + edgeDistance {
                let strength = min(1, max(0, (visibleTop + edgeDistance - location.y) / edgeDistance))
                delta = -max(minimumSpeedPerSecond, edgeSpeedPerSecond * strength) * frameStep
            } else if location.y > visibleBottom - edgeDistance {
                let strength = min(1, max(0, (location.y - (visibleBottom - edgeDistance)) / edgeDistance))
                delta = max(minimumSpeedPerSecond, edgeSpeedPerSecond * strength) * frameStep
            }
        }
        guard delta != 0 else { return }

        let minimumOffset = -scrollView.adjustedContentInset.top
        let maximumOffset = max(minimumOffset, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let nextOffset = min(maximumOffset, max(minimumOffset, scrollView.contentOffset.y + delta))
        if nextOffset != scrollView.contentOffset.y {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: nextOffset), animated: false)
        }
    }

    private func stopEdgeScrolling() {
        edgeScrollLink?.invalidate()
        edgeScrollLink = nil
        displayLinkTarget?.onTick = nil
        displayLinkTarget = nil
        activeSession = nil
        activeScrollView = nil
    }

    deinit { edgeScrollLink?.invalidate() }
}
