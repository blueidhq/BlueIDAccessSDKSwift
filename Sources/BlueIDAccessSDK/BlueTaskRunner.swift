import Combine
import Foundation

public protocol BlueTaskRunner {
    func getTasks() -> [BlueTask]
    func execute(_ throwWhenFail: Bool) async throws
    func cancel() -> Bool
    func isFailed() -> Bool
    func isCancelled() -> Bool
    func isSuccessful() -> Bool
    func getResult<ResultType>(_ id: AnyHashable) throws -> ResultType
}

enum BlueTaskStatus {
    case ready
    case started
    case failed
    case succeeded
    case skipped
}

enum BlueTaskResult {
    case resultWithStatus(Any?, BlueTaskStatus)
    case result(Any?)
}

public class BlueTask {
    let id: AnyHashable
    
    var label: CurrentValueSubject<String, Never>
    var failable: Bool = false
    var result: Any? = nil
    var error: Error? = nil
    var status: CurrentValueSubject<BlueTaskStatus, Never>
    var progress: CurrentValueSubject<Float, Never>?
    
    let handler: (BlueTask, BlueSerialTaskRunner) async throws -> BlueTaskResult
    let cancelHandler: (() -> Void)?
    
    init(
        id: AnyHashable,
        label: String,
        failable: Bool = false,
        status: BlueTaskStatus = .ready,
        error: Error? = nil,
        progress: Float? = nil,
        cancelHandler: (() -> Void)? = nil,
        handler: @escaping (BlueTask, BlueSerialTaskRunner) async throws -> BlueTaskResult
    ) {
        self.id = id
        self.label = CurrentValueSubject(label)
        self.failable = failable
        self.error = error
        self.status = .init(status)
        self.handler = handler
        self.cancelHandler = cancelHandler
        
        if let progress = progress {
            self.progress = CurrentValueSubject(progress)
        }
    }
    
    var errorDescription: String? {
        return error?.localizedDescription
    }
    
    func updateStatus(_ status: BlueTaskStatus) {
        blueRunInMainThread {
            self.status.send(status)
        }
    }
    
    func updateProgress(_ progress: Float) {
        blueRunInMainThread {
            self.progress?.send(progress)
        }
    }
    
    func updateLabel(_ label: String) {
        blueRunInMainThread {
            self.label.send(label)
        }
    }
    
    func cancel() {
        self.cancelHandler?()
    }
}

public class BlueSerialTaskRunner: BlueTaskRunner {
    private let tasks: [BlueTask]
    
    private var failed: Bool = false
    private var cancelled: Bool = false
    private var sucessful: Bool = false
    private var currentTask: BlueTask? = nil
    
    init(_ tasks: [BlueTask]) {
        self.tasks = tasks
    }
    
    public func getTasks() -> [BlueTask] {
        return tasks
    }
    
    public func execute(_ throwWhenFail: Bool) async throws {
        for task in tasks {
            if (cancelled) {
                blueLogDebug("Cancelled")
                return
            }
            
            self.currentTask = task
            
            do {
                blueLogDebug("Started: \(task.id)")
                
                task.updateStatus(.started)
                
                let taskResult = try await task.handler(task, self)
                
                let taskStatus: BlueTaskStatus
                
                switch (taskResult) {
                    case .resultWithStatus(let result, let status):
                        task.result = result
                        taskStatus = status
                        break
                        
                    case .result(let result):
                        task.result = result
                        taskStatus = .succeeded
                        break
                }
                
                task.updateStatus(taskStatus)
                
                if taskStatus == .failed {
                    if (!task.failable) {
                        failed = true
                        return
                    }
                }
                
                blueLogDebug("Finished: \(task.id)")
            } catch {
                blueLogDebug("Failed: \(task.id)")
                
                task.error = error
                task.updateStatus(.failed)
                
                if (!task.failable) {
                    failed = true
                    
                    if (throwWhenFail) {
                        throw error
                    }
                    
                    return
                }
            }
        }
        
        sucessful = true
    }
    
    public func cancel() -> Bool {
        if (!sucessful && !failed) {
            self.currentTask?.cancel()
            
            cancelled = true
            
            return true
        }
        
        return false
    }
    
    public func isSuccessful() -> Bool { sucessful }
    public func isFailed() -> Bool { failed }
    public func isCancelled() -> Bool { cancelled }
    
    public func getResult<ResultType>(_ id: AnyHashable) throws -> ResultType {
        if let task = tasks.first(where: { $0.id == id }) {
            if let result = task.result as? ResultType {
                return result
            }
        }
        
        throw BlueError(.invalidArguments)
    }
}
