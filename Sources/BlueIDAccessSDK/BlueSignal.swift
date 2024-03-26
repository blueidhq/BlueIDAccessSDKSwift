import Foundation

fileprivate class BlueSignal {
    private var key: String
    private var semaphore: DispatchSemaphore?
    
    internal var error: Error?
    internal var result: Any?
    
    internal init(_ key: String) {
        self.key = key
        semaphore = DispatchSemaphore(value: 0)
        error = nil
        result = nil
    }
    
    internal func wait(doWait: Bool) throws -> Any? {
        if (doWait) {
            semaphore?.wait()
        }
    
        if let error = self.error {
            throw error
        }
        
        return result
    }
    
    internal func success(_ result: Any? = nil) {
        if let semaphore = self.semaphore {
            self.error = nil
            self.result = result
            self.semaphore = nil
            
            semaphore.signal()
        }
    }
    
    internal func failure(_ error: Error) {
        if let semaphore = self.semaphore {
            self.error = error
            self.result = nil
            self.semaphore = nil
            
            semaphore.signal()
        }
    }
    
    internal func abort() {
        if let semaphore = self.semaphore {
            self.error = BlueError(.aborted)
            self.result = nil
            semaphore.signal()
        }
    }
}

private var blueSignalMap: [String: BlueSignal] = [:]
private var blueHistoryMap: [String: (error: Error?, result: Any?)] = [:]

internal func blueAddSignal(group: String, name: String) throws {
    let key = "\(group):\(name)"
    
    if (blueSignalMap[key] != nil) {
        blueLogWarn("BlueSignal \(name) in group \(group) already exists")
        throw BlueError(.invalidArguments)
    }
    
    blueSignalMap[key] = BlueSignal(key)
}

internal func blueRemoveSignal(group: String, name: String) {
    let key = "\(group):\(name)"
    
    if blueSignalMap[key] != nil {
        blueSignalMap.removeValue(forKey: key)
        blueLogDebug("BlueSignal \(name) in group \(group) has been removed")
    }
    
    if blueHistoryMap[key] != nil {
        blueHistoryMap.removeValue(forKey: key)
        blueLogDebug("BlueSignal \(name) in group \(group) has been removed from history map")
    }
}

internal func blueWaitSignal(group: String, name: String, signalFromHistory: Bool = false) throws -> Any? {
    let key = "\(group):\(name)"
    
    guard let signal = blueSignalMap[key] else {
        blueLogWarn("BlueSignal \(name) in group \(group) does not exists")
        throw BlueError(.notFound)
    }
    
    if let historyData = blueHistoryMap[key] {
        blueHistoryMap.removeValue(forKey: key)
        
        if (signalFromHistory) {
            // Immediately resolve it as we already got the callback data
            signal.error = historyData.error
            signal.result = historyData.result
            
            return try signal.wait(doWait: false)
        }
    }
    
    return try signal.wait(doWait: true)
}

internal func blueSignalSuccess(group: String, name: String, result: Any? = nil) {
    let key = "\(group):\(name)"
    
    guard let signal = blueSignalMap[key] else {
        blueLogInfo("BlueSignal \(name) in group \(group) does not yet exists, storing result in history data")
        blueHistoryMap[name] = (error: nil, result: result)
        return
    }
    
    signal.success(result)
}

internal func blueSignalFailure(group: String, name: String, error: Error) {
    let key = "\(group):\(name)"
    
    guard let signal = blueSignalMap[key] else {
        blueLogInfo("BlueSignal \(name) in group \(group) does not yet exists, storing error in history data")
        blueHistoryMap[name] = (error: error, result: nil)
        return
    }
    
    signal.failure(error)
}

/// Aborts the blue signal for a specified group.
///
/// - parameters:
///   - group: A string indicating the group for which the blue signal should be aborted.
internal func blueSignalAbort(group: String) {
    for (key, value) in blueSignalMap {
        let keyComponents = key.components(separatedBy: ":")
        
        if keyComponents.count >= 2 {
            if (keyComponents[0] == group) {
                value.abort()
            }
        }
    }
}

internal func blueSignalFailureGroup(group: String, error: Error) {
    for (key, value) in blueSignalMap {
        let keyComponents = key.components(separatedBy: ":")
        
        if keyComponents.count >= 2 {
            if (keyComponents[0] == group) {
                value.failure(error)
            }
        }
    }
}
