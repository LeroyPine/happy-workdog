import AppKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardCoordinator {
    var onTextChanged: ((String) -> Void)?
    var onImageChanged: ((NSImage) -> Void)?
    var onFileURLsChanged: (([URL]) -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copyTextToPasteboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func copyImageToPasteboard(_ image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount
    }

    func copyFileURLsToPasteboard(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        lastChangeCount = pasteboard.changeCount
    }

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        let fileURLs = copiedFileURLs()
        if fileURLs.count == 1 {
            if let image = imageFromCopiedFiles(fileURLs) {
                onImageChanged?(image)
                return
            }
            onFileURLsChanged?(fileURLs)
            return
        }

        if !fileURLs.isEmpty {
            onFileURLsChanged?(fileURLs)
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            onImageChanged?(image)
            return
        }

        guard let text = pasteboard.string(forType: .string) else { return }
        onTextChanged?(text)
    }

    private func imageFromCopiedFiles(_ urls: [URL]) -> NSImage? {
        for url in urls where isImageFile(url) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private func copiedFileURLs() -> [URL] {
        let readURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        let itemURLs = pasteboard.pasteboardItems?.compactMap { item -> URL? in
            guard let value = item.string(forType: .fileURL) else { return nil }
            return URL(string: value)
        } ?? []

        var seen: Set<URL> = []
        return (readURLs + itemURLs).filter { url in
            guard url.isFileURL, !seen.contains(url) else { return false }
            seen.insert(url)
            return true
        }
    }

    private func isImageFile(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .image)
        }

        guard let fileType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return fileType.conforms(to: .image)
    }
}
