import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A visible grabber keeps the native drag recognizer away from card taps,
/// horizontal swipe actions, and the vertical scroll gesture.
struct EntryDragHandle: UIViewRepresentable {
    let entry: Entry

    func makeUIView(context: Context) -> EntryDragHandleView {
        EntryDragHandleView(entry: entry)
    }

    func updateUIView(_ view: EntryDragHandleView, context: Context) {
        view.entry = entry
    }
}

/// Provides real UIKit drag callbacks for lift/drop haptics and edge scrolling.
/// The JSON UTType.data payload matches Entry's CodableRepresentation in PlanningView.
final class EntryDragHandleView: UIView, UIDragInteractionDelegate {
    var entry: Entry
    private let glyph = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
    private var dragInteraction: UIDragInteraction!
    private var activeSession: UIDragSession?
    private weak var activeScrollView: UIScrollView?
    private var edgeScrollLink: CADisplayLink?

    init(entry: Entry) {
        self.entry = entry
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        glyph.tintColor = .secondaryLabel
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        addSubview(glyph)
        dragInteraction = UIDragInteraction(delegate: self)
        dragInteraction.isEnabled = true
        addInteraction(dragInteraction)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        glyph.frame = CGRect(x: bounds.midX - 10, y: 6, width: 20, height: 18)
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let data = try? JSONEncoder().encode(entry) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return [UIDragItem(itemProvider: provider)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        let previewView = cardPreviewView ?? self
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        return UITargetedDragPreview(view: previewView, parameters: parameters)
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        activeSession = session
        activeScrollView = nearestScrollView
        guard activeScrollView != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(scrollAtEdges))
        link.add(to: .main, forMode: .common)
        edgeScrollLink = link
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, willEndWith operation: UIDropOperation) {
        if operation == .copy || operation == .move {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.85)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
        }
        stopEdgeScrolling()
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionDidEnd session: UIDragSession) {
        stopEdgeScrolling()
    }

    private var nearestScrollView: UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView { return scrollView }
            candidate = view.superview
        }
        return nil
    }

    /// The first card-sized hosting view gives the lifted item a useful card preview.
    /// If SwiftUI exposes only the handle's host here, the system uses that view instead.
    private var cardPreviewView: UIView? {
        guard let window else { return nil }
        let handleFrame = convert(bounds, to: window)
        var candidate = superview
        while let view = candidate {
            let frame = view.convert(view.bounds, to: window)
            let looksLikeCard = frame.width >= handleFrame.width * 2 &&
                frame.width <= window.bounds.width &&
                frame.height >= max(72, handleFrame.height * 1.4) &&
                frame.height <= window.bounds.height * 0.6
            if looksLikeCard { return view }
            candidate = view.superview
        }
        return nil
    }

    @objc private func scrollAtEdges() {
        guard let session = activeSession, let scrollView = activeScrollView else {
            stopEdgeScrolling()
            return
        }
        let location = session.location(in: scrollView)
        let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
        let edgeDistance: CGFloat = 72
        let edgeSpeed: CGFloat = 18
        var delta: CGFloat = 0

        if location.x >= scrollView.bounds.minX && location.x <= scrollView.bounds.maxX {
            if location.y < visibleTop + edgeDistance {
                let strength = min(1, max(0, (visibleTop + edgeDistance - location.y) / edgeDistance))
                delta = -max(2, edgeSpeed * strength)
            } else if location.y > visibleBottom - edgeDistance {
                let strength = min(1, max(0, (location.y - (visibleBottom - edgeDistance)) / edgeDistance))
                delta = max(2, edgeSpeed * strength)
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
        activeSession = nil
        activeScrollView = nil
    }

    deinit { edgeScrollLink?.invalidate() }
}
