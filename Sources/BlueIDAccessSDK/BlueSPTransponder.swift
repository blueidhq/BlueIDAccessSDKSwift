import Foundation
import CBlueIDAccess

private typealias BlueSPTransponderVtable_getTerminalPublicKey = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt16>?) -> BlueReturnCode_t

private let spTransponderCallback_getTerminalPublicKey: BlueSPTransponderVtable_getTerminalPublicKey = { context, deviceID, terminalPublicKey, terminalPublicKeySize in
    guard let context = context, let deviceID = deviceID, let terminalPublicKey = terminalPublicKey, let terminalPublicKeySize = terminalPublicKeySize else {
        return blueAsClibReturnCode(.invalidArguments)
    }
    
    let transponder : BlueSPTransponder = Unmanaged.fromOpaque(context).takeUnretainedValue()
    
    do {
        let terminalPublicKeyData = try transponder.getTerminalPublicKey(deviceID: String(cString: deviceID))
        
        try blueCopyDataToClib(data: terminalPublicKeyData, buffer: terminalPublicKey, bufferSize: UInt32(terminalPublicKeySize.pointee))
        
        terminalPublicKeySize.pointee = UInt16(terminalPublicKeyData.count)
    } catch let error as BlueError {
        return blueAsClibReturnCode(error.returnCode)
    } catch {
        return blueAsClibReturnCode(.invalidArguments)
    }
    
    return blueAsClibReturnCode(.ok)
}

internal final class BlueSPTransponder {
    private let terminalPublicKeysKeychain: BlueKeychain
    private let handlerVTablePtr: UnsafeMutablePointer<BlueSPTransponderHandlerVtable_t>
    private let handlerVTablePtrConst: UnsafePointer<BlueSPTransponderHandlerVtable_t>
    private let handlerPtr: UnsafeMutablePointer<BlueSPTransponderHandler_t>
    private let handlerPtrConst: UnsafePointer<BlueSPTransponderHandler_t>
    private let configurationPtr: UnsafeMutablePointer<BlueSPTransponderConfiguration_t>
    
    internal init (terminalPublicKeysKeychain: BlueKeychain) throws {
        self.terminalPublicKeysKeychain = terminalPublicKeysKeychain
        
        handlerVTablePtr = UnsafeMutablePointer<BlueSPTransponderHandlerVtable_t>.allocate(capacity: 1)
        handlerVTablePtr.pointee.getTerminalPublicKey = spTransponderCallback_getTerminalPublicKey
        
        handlerVTablePtrConst = UnsafePointer<BlueSPTransponderHandlerVtable_t>(handlerVTablePtr)
        
        handlerPtr = UnsafeMutablePointer<BlueSPTransponderHandler_t>.allocate(capacity: 1)
        handlerPtr.pointee.pFuncs = handlerVTablePtrConst
        
        handlerPtrConst = UnsafePointer<BlueSPTransponderHandler_t>(handlerPtr)
        
        configurationPtr = UnsafeMutablePointer<BlueSPTransponderConfiguration_t>.allocate(capacity: 1)
        configurationPtr.pointee.pHandler = handlerPtrConst
        
        handlerPtr.pointee.pContext = Unmanaged.passUnretained(self).toOpaque()
        
        _ = try blueClibErrorCheck(blueSPTransponder_Init(configurationPtr))
    }
    
    deinit {
        configurationPtr.deallocate()
        handlerPtr.deallocate()
        handlerVTablePtr.deallocate()
        
        do {
            _ = try blueClibErrorCheck(blueSPTransponder_Release())
        } catch let error as BlueError {
            fatalError(error.errorDescription!)
        } catch {
            fatalError("Unknown error while releasing sp transponder")
        }
    }
    
    fileprivate func getTerminalPublicKey(deviceID: String) throws -> Data {
        let publicKey = try terminalPublicKeysKeychain.getEntry(id: deviceID)
        
        guard let publicKey = publicKey else {
            if (deviceID == blueDemoData.deviceID) {
                return blueDemoData.terminalPublicKey
            }
            
            throw BlueError(.notFound)
        }
        
        return publicKey
    }
}

