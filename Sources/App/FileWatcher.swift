import Foundation

/// Watches a directory for any file changes using kqueue via DispatchSource.
final class FileWatcher {
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let callback: () -> Void

    init(directory: URL, onChange callback: @escaping () -> Void) {
        self.url = directory
        self.callback = callback
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        fd = open(url.path, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: DispatchQueue.main
        )
        src.setEventHandler { [weak self] in
            self?.callback()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        src.activate()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    func restart() {
        stop()
        start()
    }
}
