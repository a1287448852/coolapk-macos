import AppKit
import Foundation
import CoolapkCoreSwift
import Observation

/// APK 下载管理:URLSession 下载任务 + 暂停/续传/取消 + 任务持久化。
///
/// 对应上游 Tauri 的 download_manager.rs 控制通道 + commands.rs 的下载命令;
/// 原生版把进度回调换成 URLSession delegate,请求头复用 Rust 签名(download_headers)。
@MainActor
@Observable
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    enum TaskState: String, Codable, Hashable {
        case running, paused, completed, failed
    }

    struct DownloadTask: Identifiable, Codable, Hashable {
        let id: UUID
        var packageName: String
        var versionName: String
        var filename: String
        var urlString: String
        var state: TaskState
        var downloadedBytes: Int64 = 0
        var totalBytes: Int64 = 0
    }

    private(set) var tasks: [DownloadTask] = []
    var statusText = ""

    @ObservationIgnored private var resumeData: [UUID: Data] = [:]
    @ObservationIgnored private var liveTaskIDs: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var headers: [String: String] = [:]

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return session
    }()

    override private init() {
        super.init()
        load()
    }

    // MARK: 目录与持久化

    /// 下载目录。nonisolated:delegate 需在非隔离上下文同步定位落盘路径。
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoolapkMac", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoolapkMac", isDirectory: true)
            .appendingPathComponent("downloads.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let list = try? JSONDecoder().decode([DownloadTask].self, from: data)
        else { return }
        // 重启后 running 状态不可恢复,降级为 paused
        tasks = list.map { task in
            var task = task
            if task.state == .running { task.state = .paused }
            return task
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    // MARK: 操作

    /// 直接用 URL 开始下载(请求头来自 Rust 签名)。
    func start(url: URL, packageName: String, versionName: String) {
        if tasks.contains(where: { $0.urlString == url.absoluteString && $0.state != .failed }) {
            statusText = "该文件已在任务列表中"
            return
        }
        if headers.isEmpty {
            do {
                let json = try CoolapkApi.shared.downloadHeaders()
                guard let data = json.data(using: .utf8),
                      let map = try? JSONSerialization.jsonObject(with: data) as? [String: String]
                else {
                    statusText = "下载请求头解析失败"
                    return
                }
                headers = map
            } catch let error as CoolapkError {
                if case .Failed(let message) = error { statusText = "获取下载凭据失败:\(message)" }
                return
            } catch {
                statusText = "获取下载凭据失败:\(error.localizedDescription)"
                return
            }
        }

        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let task = session.downloadTask(with: request)
        let id = UUID()
        task.taskDescription = id.uuidString
        task.resume()

        var entry = DownloadTask(
            id: id,
            packageName: packageName,
            versionName: versionName,
            filename: url.lastPathComponent.isEmpty ? "\(packageName).apk" : url.lastPathComponent,
            urlString: url.absoluteString,
            state: .running
        )
        entry.filename = entry.filename.hasSuffix(".apk") ? entry.filename : entry.filename + ".apk"
        tasks.insert(entry, at: 0)
        save()
        statusText = ""
    }

    func pause(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), task.state == .running,
              let live = liveTaskIDs[id]
        else { return }
        live.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                self?.resumeData[id] = data
                self?.liveTaskIDs[id] = nil
                if let index = self?.tasks.firstIndex(where: { $0.id == id }) {
                    self?.tasks[index].state = .paused
                    self?.save()
                }
            }
        })
        _ = task
    }

    func resume(_ id: UUID) {
        guard var task = tasks.first(where: { $0.id == id }), task.state == .paused,
              let data = resumeData[id]
        else { return }
        let live = session.downloadTask(withResumeData: data)
        live.taskDescription = id.uuidString
        live.resume()
        resumeData[id] = nil
        liveTaskIDs[id] = live
        task.state = .running
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].state = .running
        }
        save()
        _ = task
    }

    func cancel(_ id: UUID) {
        liveTaskIDs[id]?.cancel()
        liveTaskIDs[id] = nil
        resumeData[id] = nil
        tasks.removeAll { $0.id == id }
        save()
    }

    func removeCompletedFile(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let file = Self.directory.appendingPathComponent(task.filename)
        try? FileManager.default.removeItem(at: file)
        tasks.removeAll { $0.id == id }
        save()
    }

    func reveal(_ task: DownloadTask) {
        let file = Self.directory.appendingPathComponent(task.filename)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    func open(_ task: DownloadTask) {
        let file = Self.directory.appendingPathComponent(task.filename)
        NSWorkspace.shared.open(file)
    }

    // MARK: URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            guard let index = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            self.tasks[index].downloadedBytes = totalBytesWritten
            self.tasks[index].totalBytes = totalBytesExpectedToWrite
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        // nonisolated 上下文不能同步读 MainActor 状态(self.tasks),
        // 文件名从任务原始 URL 本地推导,后缀规则与 start() 一致(非 .apk 结尾则追加)。
        var fileName = downloadTask.originalRequest?.url?.lastPathComponent ?? ""
        if fileName.isEmpty { fileName = "download.apk" }
        if !fileName.hasSuffix(".apk") { fileName += ".apk" }
        let destination = Self.directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor in self.markFailed(id: id, message: "保存文件失败:\(error.localizedDescription)") }
            return
        }
        Task { @MainActor in
            self.liveTaskIDs[id] = nil
            guard let index = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            self.tasks[index].state = .completed
            self.tasks[index].filename = fileName
            self.save()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error, !(error is URLError && error._code == NSURLErrorCancelled) else { return }
        guard let raw = task.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            self.markFailed(id: id, message: error.localizedDescription)
        }
    }

    private func markFailed(id: UUID, message: String) {
        liveTaskIDs[id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .failed
        save()
        statusText = "「\(tasks[index].packageName)」下载失败:\(message)"
    }
}
