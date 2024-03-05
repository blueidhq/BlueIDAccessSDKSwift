import Foundation

public final class BlueError: Error, LocalizedError, Equatable {
    public static var timeoutMessage = "A timeout has occurred with return code %returnCode%"
    public static var returnCodeMessage = "Error with return code %returnCode%"
    public static var unknownErrorMessage = "Unknnown error has ocurred"
    
    public let returnCode: BlueReturnCode
    
    private let cause: Error?
    private let detail: String?
    
    public var errorDescription: String? {
        var returnCodeStr = "\(returnCode.rawValue) (\(String(describing: returnCode)))"
        
        if (returnCode == .timeout || returnCode == .sdkTimeout) {
            return BlueError.timeoutMessage.replacingOccurrences(of: "%returnCode%", with: returnCodeStr)
        } else {
            if let cause = cause {
                returnCodeStr += "\nCause: \(cause.localizedDescription)"
            }
            if let detail = detail {
                returnCodeStr += "\nDetail: \(detail)"
            }
            
            return BlueError.returnCodeMessage.replacingOccurrences(of: "%returnCode%", with: returnCodeStr)
        }
    }
    
    public var failureReason: String? {
        return String(describing: returnCode)
    }
    
    public var recoverySuggestion: String? {
        return nil
    }
    
    public var helpAnchor: String? {
        return nil
    }
    
    public init(_ returnCode: BlueReturnCode) {
        self.returnCode = returnCode
        self.cause = nil
        self.detail = nil
    }
    
    public init(_ returnCode: BlueReturnCode, cause: Error, detail: String? = nil) {
        self.returnCode = returnCode
        self.cause = cause
        self.detail = detail
    }
    
    static public func == (lhs: BlueError, rhs: BlueError) -> Bool {
        return lhs.returnCode.rawValue == rhs.returnCode.rawValue
    }
}

public final class BlueTerminalError: Error, LocalizedError, Equatable {
    let terminalError: BlueError
    
    public var errorDescription: String? {
        return "Terminal error: \(terminalError.errorDescription!)"
    }
    
    public var failureReason: String? {
        return terminalError.failureReason
    }
    
    public var recoverySuggestion: String? {
        return nil
    }
    
    public var helpAnchor: String? {
        return nil
    }
    
    public init(_ returnCode: BlueReturnCode) {
        self.terminalError = BlueError(returnCode)
    }
    
    static public func == (lhs: BlueTerminalError, rhs: BlueTerminalError) -> Bool {
        return lhs.terminalError.returnCode.rawValue == rhs.terminalError.returnCode.rawValue
    }
}
