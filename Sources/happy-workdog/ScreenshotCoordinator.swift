import AppKit
import CoreGraphics

private enum ScreenshotAnnotation {
    case arrow(start: NSPoint, end: NSPoint)
    case rectangle(NSRect)
    case pen([NSPoint])
    case text(value: String, origin: NSPoint)

    func translated(by offset: NSSize) -> ScreenshotAnnotation {
        switch self {
        case .arrow(let start, let end):
            return .arrow(start: start.offset(by: offset), end: end.offset(by: offset))
        case .rectangle(let rect):
            return .rectangle(rect.offsetBy(dx: offset.width, dy: offset.height))
        case .pen(let points):
            return .pen(points.map { $0.offset(by: offset) })
        case .text(let value, let origin):
            return .text(value: value, origin: origin.offset(by: offset))
        }
    }

    var bounds: NSRect {
        switch self {
        case .arrow(let start, let end):
            return NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .rectangle(let rect):
            return rect
        case .pen(let points):
            guard let firstPoint = points.first else { return .zero }
            return points.dropFirst().reduce(
                NSRect(x: firstPoint.x, y: firstPoint.y, width: 0, height: 0)
            ) { partialResult, point in
                partialResult.union(NSRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        case .text(let value, let origin):
            let size = NSAttributedString(
                string: value,
                attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold)]
            )
            .size()
            return NSRect(origin: origin, size: size)
        }
    }

    func isNear(_ point: NSPoint, tolerance: CGFloat) -> Bool {
        switch self {
        case .arrow(let start, let end):
            return distance(from: point, toSegmentFrom: start, to: end) <= tolerance
        case .rectangle(let rect):
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && (!inner.contains(point) || inner.width <= 0 || inner.height <= 0)
        case .pen(let points):
            guard points.count > 1 else { return false }
            return zip(points, points.dropFirst()).contains {
                distance(from: point, toSegmentFrom: $0.0, to: $0.1) <= tolerance
            }
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    private func distance(from point: NSPoint, toSegmentFrom start: NSPoint, to end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(projection, 0), 1)
        let closestPoint = NSPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
    }
}

private extension NSPoint {
    func offset(by offset: NSSize) -> NSPoint {
        NSPoint(x: x + offset.width, y: y + offset.height)
    }
}

private enum ScreenshotAnnotationRenderer {
    private static let annotationColor = NSColor.systemRed
    private static let lineWidth: CGFloat = 3

    static func draw(_ annotations: [ScreenshotAnnotation], offset: NSSize = .zero) {
        for annotation in annotations.map({ $0.translated(by: offset) }) {
            draw(annotation)
        }
    }

    private static func draw(_ annotation: ScreenshotAnnotation) {
        annotationColor.setStroke()
        annotationColor.setFill()

        switch annotation {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end)
        case .rectangle(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            path.stroke()
        case .pen(let points):
            guard let firstPoint = points.first else { return }
            let path = NSBezierPath()
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .text(let value, let origin):
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: annotationColor,
                    .shadow: shadow,
                ]
            )
            .draw(at: origin)
        }
    }

    private static func drawArrow(from start: NSPoint, to end: NSPoint) {
        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 14
        let arrowAngle: CGFloat = .pi / 7
        let arrowHead = NSBezierPath()
        arrowHead.move(to: end)
        arrowHead.line(to: NSPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        ))
        arrowHead.move(to: end)
        arrowHead.line(to: NSPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        ))
        arrowHead.lineWidth = lineWidth
        arrowHead.lineCapStyle = .round
        arrowHead.lineJoinStyle = .round
        arrowHead.stroke()
    }
}

@MainActor
final class ScreenshotCoordinator {
    enum CaptureResult: Equatable {
        case captured
        case cancelled
        case permissionRequired
        case failed
    }

    var onStarted: (() -> Void)?
    var onCompleted: ((CaptureResult) -> Void)?

    private(set) var isCapturing = false
    private let pasteboard: NSPasteboard
    private var selectionOverlayController: ScreenshotSelectionOverlayController?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func requestScreenCapturePermissionIfNeeded() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    func captureSelectionToClipboard(after delay: TimeInterval = 0) {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            onCompleted?(.permissionRequired)
            return
        }
        isCapturing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.presentSelectionOverlay()
        }
    }

    private func presentSelectionOverlay() {
        guard CGPreflightScreenCaptureAccess() else {
            finish(with: .permissionRequired)
            return
        }

        let overlayController = ScreenshotSelectionOverlayController()
        overlayController.onCompleted = { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.finish(with: .cancelled)
                return
            }

            self.pasteboard.clearContents()
            guard self.pasteboard.writeObjects([image]) else {
                self.finish(with: .failed)
                return
            }
            self.finish(with: .captured)
        }
        selectionOverlayController = overlayController

        guard overlayController.present() else {
            finish(with: CGPreflightScreenCaptureAccess() ? .failed : .permissionRequired)
            return
        }
        onStarted?()
    }

    private func finish(with result: CaptureResult) {
        selectionOverlayController?.dismiss()
        selectionOverlayController = nil
        isCapturing = false
        onCompleted?(result)
    }
}

@MainActor
private final class ScreenshotSelectionOverlayController {
    var onCompleted: ((NSImage?) -> Void)?

    private var windows: [ScreenshotSelectionWindow] = []
    private var isFinished = false

    func present() -> Bool {
        guard windows.isEmpty else { return false }

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let image = CGDisplayCreateImage(CGDirectDisplayID(screenNumber.uint32Value))
            else { continue }

            let selectionView = ScreenshotSelectionView(snapshot: image, screenSize: screen.frame.size)
            selectionView.onSelected = { [weak self] image in
                self?.complete(with: image)
            }
            selectionView.onCancel = { [weak self] in
                self?.complete(with: nil)
            }

            let window = ScreenshotSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = selectionView
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            windows.append(window)
        }

        guard !windows.isEmpty else { return false }

        for window in windows {
            window.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        let mouseLocation = NSEvent.mouseLocation
        let activeWindow = windows.first(where: { $0.frame.contains(mouseLocation) }) ?? windows[0]
        activeWindow.makeKeyAndOrderFront(nil)
        activeWindow.makeFirstResponder(activeWindow.contentView)
        NSCursor.crosshair.set()
        return true
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }

    private func complete(with image: NSImage?) {
        guard !isFinished else { return }
        isFinished = true
        onCompleted?(image)
    }

}

private final class ScreenshotSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
    var onSelected: ((NSImage) -> Void)?
    var onCancel: (() -> Void)?

    private enum AnnotationTool: CaseIterable {
        case arrow
        case rectangle
        case pen
        case text

        var symbolName: String {
            switch self {
            case .arrow:
                return "arrow.up.right"
            case .rectangle:
                return "rectangle"
            case .pen:
                return "pencil.tip"
            case .text:
                return "textformat"
            }
        }
    }

    private enum ResizeHandle: CaseIterable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left
    }

    private enum DragMode {
        case creating(start: NSPoint)
        case moving(start: NSPoint, originalRect: NSRect)
        case resizing(handle: ResizeHandle, originalRect: NSRect)
        case movingAnnotation(index: Int, start: NSPoint, original: ScreenshotAnnotation)
        case drawingArrow(start: NSPoint)
        case drawingRectangle(start: NSPoint)
        case drawingPen(points: [NSPoint])
    }

    private let snapshot: NSImage
    private let snapshotCGImage: CGImage
    private var selectionRect = NSRect.zero
    private var dragMode: DragMode?
    private var annotations: [ScreenshotAnnotation] = []
    private var activeAnnotationTool: AnnotationTool?
    private var previewAnnotation: ScreenshotAnnotation?
    private var selectedAnnotationIndex: Int?
    private var textField: NSTextField?

    private let handleSize: CGFloat = 9
    private let handleHitSize: CGFloat = 18
    private let minimumSelectionSize: CGFloat = 12
    private let buttonSize = NSSize(width: 34, height: 28)
    private let buttonSpacing: CGFloat = 8
    private let toolButtonSize = NSSize(width: 34, height: 30)
    private let toolButtonSpacing: CGFloat = 4

    init(snapshot: CGImage, screenSize: NSSize) {
        self.snapshotCGImage = snapshot
        self.snapshot = NSImage(cgImage: snapshot, size: screenSize)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        guard hasSelection else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }

        addCursorRect(bounds, cursor: .crosshair)
        addCursorRect(selectionRect, cursor: activeAnnotationTool == nil ? .openHand : .crosshair)

        if activeAnnotationTool == nil {
            for handle in ResizeHandle.allCases {
                addCursorRect(handleHitRect(for: handle), cursor: cursor(for: handle))
            }
        }

        for tool in AnnotationTool.allCases {
            addCursorRect(toolButtonRect(for: tool), cursor: .pointingHand)
        }
        addCursorRect(cancelButtonRect, cursor: .pointingHand)
        addCursorRect(confirmButtonRect, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.46).setFill()
        bounds.fill()

        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        snapshot.draw(in: selectionRect, from: selectionRect, operation: .copy, fraction: 1)

        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        drawAnnotations()
        if activeAnnotationTool == nil {
            drawHandles()
        }
        drawSizeLabel()
        drawAnnotationToolbar()
        drawActionButtons()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = constrainedPoint(for: event)

        if hasSelection, let tool = annotationTool(at: point) {
            activeAnnotationTool = activeAnnotationTool == tool ? nil : tool
            discardTextField()
            resetCursorRects()
            needsDisplay = true
            return
        }

        if hasSelection {
            if confirmButtonRect.contains(point) {
                dragMode = nil
                finishSelection()
                return
            }
            if cancelButtonRect.contains(point) {
                dragMode = nil
                onCancel?()
                return
            }

            if let activeAnnotationTool, selectionRect.contains(point) {
                selectedAnnotationIndex = nil
                beginAnnotation(activeAnnotationTool, at: point)
                return
            }

            if activeAnnotationTool == nil, let annotationIndex = annotationIndex(at: point) {
                selectedAnnotationIndex = annotationIndex
                dragMode = .movingAnnotation(
                    index: annotationIndex,
                    start: point,
                    original: annotations[annotationIndex]
                )
                needsDisplay = true
                return
            }

            if activeAnnotationTool == nil, let handle = resizeHandle(at: point) {
                selectedAnnotationIndex = nil
                dragMode = .resizing(handle: handle, originalRect: selectionRect)
                return
            }
            if activeAnnotationTool == nil, selectionRect.contains(point) {
                selectedAnnotationIndex = nil
                dragMode = .moving(start: point, originalRect: selectionRect)
                return
            }
        }

        selectionRect = .zero
        annotations.removeAll()
        activeAnnotationTool = nil
        previewAnnotation = nil
        selectedAnnotationIndex = nil
        discardTextField()
        dragMode = .creating(start: point)
        resetCursorRects()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateSelection(with: event)

        if let previewAnnotation {
            annotations.append(previewAnnotation)
            selectedAnnotationIndex = annotations.indices.last
            self.previewAnnotation = nil
        }
        dragMode = nil

        guard selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize
        else {
            selectionRect = .zero
            resetCursorRects()
            needsDisplay = true
            return
        }

        resetCursorRects()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if textField != nil {
                discardTextField()
                return
            }
            onCancel?()
            return
        }
        if event.keyCode == 36, hasSelection {
            if textField != nil {
                commitTextField()
                return
            }
            finishSelection()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLastAnnotation()
            return
        }
        super.keyDown(with: event)
    }

    private func updateSelection(with event: NSEvent) {
        guard let dragMode else { return }
        let current = constrainedPoint(for: event)

        switch dragMode {
        case .creating(let start):
            selectionRect = rect(from: start, to: current)
        case .moving(let start, let originalRect):
            selectionRect = movedRect(
                originalRect,
                by: NSSize(width: current.x - start.x, height: current.y - start.y)
            )
        case .resizing(let handle, let originalRect):
            selectionRect = resizedRect(originalRect, using: handle, to: current)
        case .movingAnnotation(let index, let start, let original):
            annotations[index] = movedAnnotation(
                original,
                by: NSSize(width: current.x - start.x, height: current.y - start.y)
            )
        case .drawingArrow(let start):
            previewAnnotation = .arrow(start: start, end: current)
        case .drawingRectangle(let start):
            previewAnnotation = .rectangle(rect(from: start, to: current))
        case .drawingPen(var points):
            points.append(current)
            self.dragMode = .drawingPen(points: points)
            previewAnnotation = .pen(points)
        }

        resetCursorRects()
        needsDisplay = true
    }

    private var hasSelection: Bool {
        selectionRect.width >= minimumSelectionSize && selectionRect.height >= minimumSelectionSize
    }

    private func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        .intersection(bounds)
    }

    private func movedRect(_ originalRect: NSRect, by offset: NSSize) -> NSRect {
        let x = min(max(originalRect.minX + offset.width, bounds.minX), bounds.maxX - originalRect.width)
        let y = min(max(originalRect.minY + offset.height, bounds.minY), bounds.maxY - originalRect.height)
        return NSRect(x: x, y: y, width: originalRect.width, height: originalRect.height)
    }

    private func movedAnnotation(_ annotation: ScreenshotAnnotation, by proposedOffset: NSSize) -> ScreenshotAnnotation {
        let originalBounds = annotation.bounds
        let minOffsetX = selectionRect.minX - originalBounds.minX
        let maxOffsetX = selectionRect.maxX - originalBounds.maxX
        let minOffsetY = selectionRect.minY - originalBounds.minY
        let maxOffsetY = selectionRect.maxY - originalBounds.maxY
        let offset = NSSize(
            width: min(max(proposedOffset.width, minOffsetX), maxOffsetX),
            height: min(max(proposedOffset.height, minOffsetY), maxOffsetY)
        )
        return annotation.translated(by: offset)
    }

    private func annotationIndex(at point: NSPoint) -> Int? {
        annotations.indices.reversed().first {
            annotations[$0].isNear(point, tolerance: 8)
        }
    }

    private func resizedRect(
        _ originalRect: NSRect,
        using handle: ResizeHandle,
        to point: NSPoint
    ) -> NSRect {
        var minX = originalRect.minX
        var maxX = originalRect.maxX
        var minY = originalRect.minY
        var maxY = originalRect.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minX = min(point.x, maxX - minimumSelectionSize)
        case .topRight, .right, .bottomRight:
            maxX = max(point.x, minX + minimumSelectionSize)
        case .top, .bottom:
            break
        }

        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            minY = min(point.y, maxY - minimumSelectionSize)
        case .topLeft, .top, .topRight:
            maxY = max(point.y, minY + minimumSelectionSize)
        case .left, .right:
            break
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(bounds)
    }

    private func constrainedPoint(for event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func beginAnnotation(_ tool: AnnotationTool, at point: NSPoint) {
        switch tool {
        case .arrow:
            dragMode = .drawingArrow(start: point)
        case .rectangle:
            dragMode = .drawingRectangle(start: point)
        case .pen:
            dragMode = .drawingPen(points: [point])
        case .text:
            presentTextField(at: point)
        }
    }

    private func finishSelection() {
        commitTextField()
        guard let image = renderedSelectionImage() else { return }
        onSelected?(image)
    }

    private func renderedSelectionImage() -> NSImage? {
        guard selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize
        else { return nil }

        let scaleX = CGFloat(snapshotCGImage.width) / bounds.width
        let scaleY = CGFloat(snapshotCGImage.height) / bounds.height
        let pixelBounds = NSRect(x: 0, y: 0, width: snapshotCGImage.width, height: snapshotCGImage.height)
        let pixelRect = NSRect(
            x: selectionRect.minX * scaleX,
            y: (bounds.height - selectionRect.maxY) * scaleY,
            width: selectionRect.width * scaleX,
            height: selectionRect.height * scaleY
        )
        .integral
        .intersection(pixelBounds)

        guard pixelRect.width > 0,
              pixelRect.height > 0,
              let croppedImage = snapshotCGImage.cropping(to: pixelRect)
        else { return nil }

        guard let context = CGContext(
            data: nil,
            width: croppedImage.width,
            height: croppedImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(croppedImage, in: NSRect(x: 0, y: 0, width: croppedImage.width, height: croppedImage.height))
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        context.scaleBy(x: scaleX, y: scaleY)
        ScreenshotAnnotationRenderer.draw(
            annotations,
            offset: NSSize(width: -selectionRect.minX, height: -selectionRect.minY)
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let composedImage = context.makeImage() else { return nil }
        return NSImage(cgImage: composedImage, size: selectionRect.size)
    }

    private func presentTextField(at point: NSPoint) {
        commitTextField()

        let fieldWidth = min(220, max(40, selectionRect.width))
        let field = NSTextField(frame: NSRect(
            x: min(max(point.x, selectionRect.minX), selectionRect.maxX - fieldWidth),
            y: max(selectionRect.minY, point.y - 14),
            width: fieldWidth,
            height: 28
        ))
        field.font = .systemFont(ofSize: 18, weight: .semibold)
        field.textColor = .systemRed
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextFieldAction(_:))
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitTextFieldAction(_ sender: Any?) {
        commitTextField()
    }

    private func commitTextField() {
        guard let field = textField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            annotations.append(.text(value: value, origin: NSPoint(x: field.frame.minX, y: field.frame.minY + 3)))
            selectedAnnotationIndex = annotations.indices.last
        }
        discardTextField()
        needsDisplay = true
    }

    private func discardTextField() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }

    private func undoLastAnnotation() {
        discardTextField()
        if !annotations.isEmpty {
            annotations.removeLast()
            selectedAnnotationIndex = nil
            needsDisplay = true
        }
    }

    private func drawAnnotations() {
        ScreenshotAnnotationRenderer.draw(annotations)
        if let previewAnnotation {
            ScreenshotAnnotationRenderer.draw([previewAnnotation])
        }
    }

    private func drawSizeLabel() {
        let label = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributedLabel = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributedLabel.size()
        let labelSize = NSSize(width: textSize.width + 12, height: textSize.height + 6)
        let proposedY = selectionRect.minY - labelSize.height - 6
        let labelOrigin = NSPoint(
            x: min(selectionRect.minX, bounds.maxX - labelSize.width),
            y: proposedY >= bounds.minY ? proposedY : min(selectionRect.maxY + 6, bounds.maxY - labelSize.height)
        )
        let labelRect = NSRect(origin: labelOrigin, size: labelSize)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        attributedLabel.draw(
            at: NSPoint(
                x: labelRect.minX + 6,
                y: labelRect.minY + 3
            )
        )
    }

    private func drawHandles() {
        NSColor.white.setFill()
        NSColor.systemBlue.setStroke()

        for handle in ResizeHandle.allCases {
            let path = NSBezierPath(ovalIn: handleRect(for: handle))
            path.fill()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawActionButtons() {
        drawToolbarBackground(in: actionButtonsBackgroundRect)
        drawActionButton(
            in: cancelButtonRect,
            symbolName: "xmark",
            fillColor: NSColor.systemRed,
            symbolColor: .white
        )
        drawActionButton(
            in: confirmButtonRect,
            symbolName: "checkmark",
            fillColor: NSColor.systemBlue,
            symbolColor: .white
        )
    }

    private func drawAnnotationToolbar() {
        drawToolbarBackground(in: annotationToolbarRect)

        for tool in AnnotationTool.allCases {
            let rect = toolButtonRect(for: tool)
            let isActive = activeAnnotationTool == tool

            (isActive ? NSColor.systemRed : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
            let buttonPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
            buttonPath.fill()

            if activeAnnotationTool == tool {
                NSColor.systemRed.setStroke()
            } else {
                NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
            }
            buttonPath.lineWidth = 1
            buttonPath.stroke()

            drawSymbol(
                tool.symbolName,
                in: rect,
                pointSize: 15,
                color: isActive ? .white : NSColor(calibratedWhite: 0.18, alpha: 1)
            )
        }
    }

    private func drawToolbarBackground(in rect: NSRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawActionButton(
        in rect: NSRect,
        symbolName: String,
        fillColor: NSColor,
        symbolColor: NSColor
    ) {
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        drawSymbol(symbolName, in: rect, pointSize: 15, color: symbolColor)
    }

    private func drawSymbol(_ symbolName: String, in rect: NSRect, pointSize: CGFloat, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }

        image.isTemplate = true
        color.set()
        let imageSize = image.size
        image.draw(
            at: NSPoint(
                x: rect.midX - imageSize.width / 2,
                y: rect.midY - imageSize.height / 2
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private var actionButtonsY: CGFloat {
        annotationToolbarRect.minY + (annotationToolbarRect.height - buttonSize.height) / 2
    }

    private var annotationToolbarRect: NSRect {
        let width = CGFloat(AnnotationTool.allCases.count) * toolButtonSize.width
            + CGFloat(AnnotationTool.allCases.count - 1) * toolButtonSpacing
            + 8
        let proposedY = selectionRect.minY - toolButtonSize.height - 10
        let y: CGFloat
        if proposedY >= bounds.minY {
            y = proposedY
        } else {
            y = min(selectionRect.maxY + 10, bounds.maxY - toolButtonSize.height - 8)
        }
        return NSRect(
            x: controlsOriginX,
            y: y,
            width: width,
            height: toolButtonSize.height + 8
        )
    }

    private var controlsOriginX: CGFloat {
        let toolbarWidth = CGFloat(AnnotationTool.allCases.count) * toolButtonSize.width
            + CGFloat(AnnotationTool.allCases.count - 1) * toolButtonSpacing
            + 8
        let totalWidth = toolbarWidth + 10 + buttonSize.width * 2 + buttonSpacing
        return min(max(selectionRect.minX, bounds.minX), bounds.maxX - totalWidth)
    }

    private func toolButtonRect(for tool: AnnotationTool) -> NSRect {
        guard let index = AnnotationTool.allCases.firstIndex(of: tool) else { return .zero }
        return NSRect(
            x: annotationToolbarRect.minX + 4 + CGFloat(index) * (toolButtonSize.width + toolButtonSpacing),
            y: annotationToolbarRect.minY + 4,
            width: toolButtonSize.width,
            height: toolButtonSize.height
        )
    }

    private func annotationTool(at point: NSPoint) -> AnnotationTool? {
        AnnotationTool.allCases.first { toolButtonRect(for: $0).contains(point) }
    }

    private var confirmButtonRect: NSRect {
        return NSRect(
            x: cancelButtonRect.maxX + buttonSpacing,
            y: actionButtonsY,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    private var actionButtonsBackgroundRect: NSRect {
        cancelButtonRect.union(confirmButtonRect).insetBy(dx: -4, dy: -5)
    }

    private var cancelButtonRect: NSRect {
        NSRect(
            x: annotationToolbarRect.maxX + 10,
            y: actionButtonsY,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    private func resizeHandle(at point: NSPoint) -> ResizeHandle? {
        ResizeHandle.allCases.first { handleHitRect(for: $0).contains(point) }
    }

    private func handleRect(for handle: ResizeHandle) -> NSRect {
        rect(centeredAt: handlePoint(for: handle), size: handleSize)
    }

    private func handleHitRect(for handle: ResizeHandle) -> NSRect {
        rect(centeredAt: handlePoint(for: handle), size: handleHitSize)
    }

    private func handlePoint(for handle: ResizeHandle) -> NSPoint {
        switch handle {
        case .topLeft:
            return NSPoint(x: selectionRect.minX, y: selectionRect.maxY)
        case .top:
            return NSPoint(x: selectionRect.midX, y: selectionRect.maxY)
        case .topRight:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        case .right:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.midY)
        case .bottomRight:
            return NSPoint(x: selectionRect.maxX, y: selectionRect.minY)
        case .bottom:
            return NSPoint(x: selectionRect.midX, y: selectionRect.minY)
        case .bottomLeft:
            return NSPoint(x: selectionRect.minX, y: selectionRect.minY)
        case .left:
            return NSPoint(x: selectionRect.minX, y: selectionRect.midY)
        }
    }

    private func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .crosshair
        case .topRight, .bottomLeft:
            return .crosshair
        }
    }

    private func rect(centeredAt point: NSPoint, size: CGFloat) -> NSRect {
        NSRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        )
    }
}
