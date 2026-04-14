import Foundation

public final class ConfigWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable () -> Void

    private let directory: URL
    private let onChange: ChangeHandler
    private var source: DispatchSourceFileSystemObject?
    private var dirFd: Int32 = -1
    private let queue = DispatchQueue(label: "deck.config-watcher", qos: .utility)
    private var debounceWork: DispatchWorkItem?

    public init(directory: URL = ConfigLoader.defaultConfigDirectory, onChange: @escaping ChangeHandler) {
        self.directory = directory
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() throws {
        try ConfigLoader.ensureConfigDirectory(at: directory)

        dirFd = open(directory.path, O_EVTONLY)
        guard dirFd >= 0 else {
            throw ConfigWatcherError.cannotWatch(directory.path)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFd, fd >= 0 {
                close(fd)
                self?.dirFd = -1
            }
        }

        self.source = source
        source.resume()
    }

    public func stop() {
        debounceWork?.cancel()
        source?.cancel()
        source = nil
    }

    private func handleChange() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

public enum ConfigWatcherError: Error, CustomStringConvertible {
    case cannotWatch(String)

    public var description: String {
        switch self {
        case .cannotWatch(let path):
            return "Cannot watch directory: \(path)"
        }
    }
}
