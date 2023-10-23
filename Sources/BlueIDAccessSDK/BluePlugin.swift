import Foundation
import SwiftProtobuf

public typealias BluePluginResolve = ([String: Any]?) -> Void
public typealias BluePluginReject = ([String: Any]) -> Void

private func convertArg(_ value: Any?) -> Any? {
    if let value = value as? String {
        if (value.starts(with: "message:")) {
            let base64: String = String(value[value.index(value.startIndex, offsetBy: 8)...])
            return Data(base64Encoded: base64)
        }
    }
    
    return value
}

private func convertResult(_ result: Any) -> Any {
    if let result = result as? Data {
        return "message:\(result.base64EncodedString())"
    }
    
    return result
}

private func rejectError(error: Error, reject: BluePluginReject) -> Void {
    if let error = error as? BlueError {
        reject([
            "error": error.returnCode.rawValue,
            "message": error.localizedDescription
        ])
    } else {
        reject([
            "error": BlueReturnCode.error.rawValue,
            "message": error.localizedDescription
        ])
    }
}

internal protocol BluePluginDelegate {
    func listenerEvent(eventName: String, eventData: [String: Any])
}

internal class BluePlugin: BlueEventListener {
    internal var delegate: BluePluginDelegate? = nil
    
    internal init(delegate: BluePluginDelegate? = nil) {
        self.delegate = delegate
    }
    
    internal func runCommand(command: String, arg0: Any?, arg1: Any?, arg2: Any?, resolve: @escaping BluePluginResolve, reject: @escaping BluePluginReject) {
        let convertedArg0 = convertArg(arg0)
        let convertedArg1 = convertArg(arg1)
        let convertedArg2 = convertArg(arg2)
        
        if (command == "initialize") {
            blueAddEventListener(listener: self)
        } else if (command == "release") {
            blueRemoveEventListener(listener: self)
        }
        
        blueRunCommand(command, arg0: convertedArg0, arg1: convertedArg1, arg2: convertedArg2) { result in
            switch result {
            case .success(let commandResult):
                if let data = commandResult.data as? Data {
                    guard let messageTypeName = commandResult.messageTypeName else {
                        reject([
                            "error": BlueReturnCode.invalidArguments.rawValue,
                            "message:": "Missing messageTypeName on request"
                        ])
                        
                        return
                    }
                    
                    resolve([
                        "data": convertResult(data),
                        "messageTypeName": messageTypeName,
                    ])
                } else if let data = commandResult.data {
                    resolve(["data": data])
                } else {
                    resolve(nil)
                }
                break
            case .failure(let error):
                rejectError(error: error, reject: reject)
                break
            }
        }
    }
    
    internal func terminalRun(deviceID: String, timeoutSeconds: Double, requestValues: [Any], resolve: @escaping BluePluginResolve, reject: @escaping BluePluginReject, isTest: Bool) {
        var requests: [BlueTerminalRequest] = []
        
        do {
            requests = try requestValues.map { value in
                guard let value = value as? [String: Any] else {
                    throw BlueError(.invalidArguments)
                }
                
                guard let action = value["action"] as? String, !action.isEmpty else {
                    throw BlueError(.invalidArguments)
                }
                
                guard let dataString = value["data"] as? String? else {
                    throw BlueError(.invalidArguments)
                }
                
                var data: Data? = nil
                
                if let dataString = dataString {
                    let dataArg = convertArg(dataString)
                    
                    if let dataArg = dataArg as? Data {
                        data = dataArg
                    } else {
                        throw BlueError(.invalidArguments)
                    }
                }
                
                return BlueTerminalRequest(action: action, data: data)
            }
        } catch {
            rejectError(error: error, reject: reject)
            return
        }
        
        blueTerminalRun(deviceID: deviceID, timeoutSeconds: timeoutSeconds, requests: requests, completion: { result in
            switch result {
            case .success(let requestResults):
                resolve([
                    "results":
                        requestResults.map({ requestResult in
                            if let data = requestResult.data {
                                return [
                                    "statusCode": requestResult.statusCode.rawValue,
                                    "data": convertResult(data)
                                ] as [String: Any]
                            } else {
                                return [
                                    "statusCode": requestResult.statusCode.rawValue
                                ] as [String: Any]
                            }
                        })
                ])
                break
            case .failure(let error):
                rejectError(error: error, reject: reject)
                break
            }
        }, isTest: isTest)
    }
    
    private func fireListener(eventName: String, eventData: [String: Any]) {
        if let delegate = self.delegate {
            delegate.listenerEvent(eventName: eventName, eventData: eventData)
        }
    }
    
    public func blueEvent(event: BlueEventType, data: Any?) {
        var eventData: [String: Any] = [:]
        
        // Some callbacks must have their data converted
        
        if (event == .terminalResult) {
            let requestResult = data as! BlueTerminalResult
            if let resultData = requestResult.data {
                eventData = [
                    "statusCode": requestResult.statusCode.rawValue,
                    "data": convertResult(resultData)
                ] as [String: Any]
            } else {
                eventData = [
                    "statusCode": requestResult.statusCode.rawValue
                ] as [String: Any]
            }
        } else if let data = data as? Message {
            do {
                let resultData = convertResult(try blueEncodeMessage(data))
                let messageTypeName = String(describing: Mirror(reflecting: data).subjectType)
                
                eventData = ["data": resultData, "messageTypeName": messageTypeName]
            } catch {
                eventData = ["data": "<error>"]
                print(error.localizedDescription)
            }
        } else if let data = data {
            eventData = ["data": data]
        }
        
        fireListener(eventName: event.rawValue, eventData: eventData)
    }
}
