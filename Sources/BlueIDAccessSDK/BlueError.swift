import Foundation

public final class BlueError: Error, LocalizedError, Equatable {
    public static var timeoutMessage = "A timeout has occurred"
    public static var returnCodeMessage = "Error with return code %returnCode%"
    public static var unknownErrorMessage = "Unknnown error has ocurred"
    
    public let returnCode: BlueReturnCode
    
    public var errorDescription: String? {
        if (returnCode == .timeout) {
            return BlueError.timeoutMessage
        } else {
            let returnCodeStr = "\(returnCode.rawValue) (\(String(describing: returnCode)))"
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
