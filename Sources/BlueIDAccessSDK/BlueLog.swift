import Foundation
import CBlueIDAccess

internal func log(level: UInt32, file: String, line: Int32, message: String) {
    blueLog_LogMsg(Int32(level), file, line, message)
}

internal func blueLogDebug(_ message: String, file: String = #file, line: Int32 = #line) {
    log(level: BlueLogSeverity_Debug.rawValue, file: file, line: line, message: message)
}

internal func blueLogInfo(_ message: String, file: String = #file, line: Int32 = #line) {
    log(level: BlueLogSeverity_Info.rawValue, file: file, line: line, message: message)
}

internal func blueLogWarn(_ message: String, file: String = #file, line: Int32 = #line) {
    log(level: BlueLogSeverity_Warn.rawValue, file: file, line: line, message: message)
}

internal func blueLogError(_ message: String, file: String = #file, line: Int32 = #line) {
    log(level: BlueLogSeverity_Error.rawValue, file: file, line: line, message: message)
}

//
// Implement the required print_log function from the c-lib
//
@_cdecl("blueLog_PrintLog")
internal func blueLog_PrintLog(_ ev: UnsafeMutablePointer<BlueLogEvent>) {
    let now = Date()
    
    let bufferSize: Int = 1024
    var buffer: [CChar] = [CChar](repeating: 0, count: bufferSize)
    
    blueLog_FormatMessage(ev, &buffer, UInt32(bufferSize))
    
    let message: String = String(cString: buffer)
    let file = String(cString: ev.pointee.pFile)
    let line = ev.pointee.line
    
    let severityStrings: [String] = [
        "",
        "ERROR",
        "WARN",
        "INFO",
        "DEBUG",
    ]
    
    let severityStr = severityStrings[Int(ev.pointee.severity)]
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss.SSS"
    
    print("\(dateFormatter.string(from: now)) <\(severityStr)>: \(message) (\(file):\(line))")
    fflush(stdout)
}
