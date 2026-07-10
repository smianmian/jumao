import Darwin
import Foundation

final class StatusFileWatcher {
  private let eventQueue = DispatchQueue(label: "com.smianmian.JumaoCat.status-watcher")
  private let queueKey = DispatchSpecificKey<Void>()
  private let debounceInterval: DispatchTimeInterval
  private let onChange: () -> Void
  private var source: DispatchSourceFileSystemObject?
  private var workspaceURL: URL?
  private var pendingChange: DispatchWorkItem?

  init(debounceInterval: DispatchTimeInterval = .milliseconds(150), onChange: @escaping () -> Void) {
    self.debounceInterval = debounceInterval
    self.onChange = onChange
    eventQueue.setSpecific(key: queueKey, value: ())
  }

  deinit {
    stop()
  }

  func start(watching workspaceURL: URL) {
    performSynchronously {
      self.workspaceURL = workspaceURL
      installSource(for: workspaceURL)
    }
  }

  func stop() {
    performSynchronously {
      workspaceURL = nil
      pendingChange?.cancel()
      pendingChange = nil
      cancelSource()
    }
  }

  private func performSynchronously(_ work: () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      work()
    } else {
      eventQueue.sync(execute: work)
    }
  }

  private func installSource(for workspaceURL: URL) {
    pendingChange?.cancel()
    pendingChange = nil
    cancelSource()

    let jumaoDirectory = workspaceURL.appendingPathComponent(".jumao", isDirectory: true)
    let watchedURL = FileManager.default.fileExists(atPath: jumaoDirectory.path)
      ? jumaoDirectory
      : workspaceURL
    let descriptor = open(watchedURL.path, O_EVTONLY)

    guard descriptor >= 0 else {
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete, .extend, .attrib],
      queue: eventQueue
    )
    source.setEventHandler { [weak self] in
      self?.scheduleChange()
    }
    source.setCancelHandler {
      close(descriptor)
    }
    self.source = source
    source.resume()
  }

  private func cancelSource() {
    source?.cancel()
    source = nil
  }

  private func scheduleChange() {
    pendingChange?.cancel()

    let work = DispatchWorkItem { [weak self] in
      guard let self, let workspaceURL else { return }
      pendingChange = nil
      installSource(for: workspaceURL)
      onChange()
    }

    pendingChange = work
    eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
  }
}
