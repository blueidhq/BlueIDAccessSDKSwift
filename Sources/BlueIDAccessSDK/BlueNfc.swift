import Foundation

import CBlueIDAccess

#if os(iOS)
import CoreNFC

private var blueNfcSession: NFCTagReaderSession? = nil
private let blueNfcSessionListener = BlueNfcSessionListener()

private final class BlueNfcSessionListener: NSObject, NFCTagReaderSessionDelegate {
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // NOOP
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if blueNfcSession != nil {
            blueSignalFailure(group: "nfc", name: "connect", error: error)
        }
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if blueNfcSession != nil {
            var tag: NFCTag? = nil
            
            for nfcTag in tags {
                // For now we only support ISO7816 transponders
                if case .iso7816(_) = nfcTag {
                    tag = nfcTag
                }
            }
            
            guard let tag = tag else {
                blueSignalFailure(group: "nfc", name: "connect", error: BlueError(.invalidTransponder))
                return
            }
            
            session.connect(to: tag) { error in
                if let error = error {
                    blueSignalFailure(group: "nfc", name: "connect", error: error)
                } else {
                    blueSignalSuccess(group: "nfc", name: "connect")
                }
            }
        }
    }
}

internal func blueNfcExecute(_ handler: @escaping (_: BlueTransponderType) throws -> String, timeoutSeconds: Double = 0) throws {
    try blueExecuteWithTimeout({
        let isActive = blueNfcSession != nil
        
        if (!NFCTagReaderSession.readingAvailable || isActive) {
            throw BlueError(.unavailable)
        }
        
        try blueAddSignal(group: "nfc", name: "connect")
        
        defer { blueRemoveSignal(group: "nfc", name: "connect") }
        
        blueNfcSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: blueNfcSessionListener, queue: blueDeviceQueue)
        
        defer {
            blueNfcSession?.invalidate()
            blueNfcSession = nil
        }
        
        guard let session = blueNfcSession else {
            throw BlueError(.invalidState)
        }
        
        session.begin()
        session.alertMessage = blueI18n.nfcWaitMessage
        
        do {
            _ = try blueWaitSignal(group: "nfc", name: "connect")
            
            guard session.connectedTag != nil else {
                throw BlueError(.invalidState)
            }
            
            var transponderType: BlueTransponderType = .unknownTransponder
            
            // TODO : How to figure and verify the card type here?
            transponderType = .mifareDesfire
            
            if (transponderType == .unknownTransponder) {
                throw BlueNativeSDKError(.invalidTransponder)
            }
            
            let successMessage = try handler(transponderType)
            
            session.alertMessage = successMessage;
            session.invalidate()
            
            blueNfcSession = nil
        } catch let error {
            var errorMessage = BlueError.unknownErrorMessage
            
            if (error.localizedDescription != "") {
                errorMessage = error.localizedDescription
            }
            
            session.invalidate(errorMessage: errorMessage)
            
            blueNfcSession = nil
            
            throw error
        }
    }, timeoutSeconds: timeoutSeconds)
}

//
// Implement the required blueNfc_Transceive function from the c-lib
//

@_cdecl("blueNfc_Transceive")
internal func blueNfc_Transceive(_ pCommandApdu: UnsafePointer<UInt8>, _ commandApduLength: UInt32, _ pResponseApdu: UnsafeMutablePointer<UInt8>, _ pResponseApduLength: UnsafeMutablePointer<UInt32>) -> BlueReturnCode_t {
    guard let session = blueNfcSession else {
        return blueAsClibReturnCode(.invalidState)
    }
    
    guard let connectedTag = session.connectedTag else {
        return blueAsClibReturnCode(.invalidState)
    }
    
    guard case let NFCTag.iso7816(apduTag) = connectedTag else {
        return blueAsClibReturnCode(.invalidState)
    }
    
    let data = Data(bytes: pCommandApdu, count: Int(commandApduLength))
    
    guard let apdu = NFCISO7816APDU(data: data) else {
        return blueAsClibReturnCode(.invalidState)
    }
    
    var apduResponse = Data()
    
    let waitSemaphore = DispatchSemaphore(value: 0)
    
    apduTag.sendCommand(apdu: apdu) { responseData, sw1, sw2, error in
        if error == nil {
            var swChar: [UInt8] = [0, 0]
            swChar[0] = sw1
            swChar[1] = sw2
            
            apduResponse.append(responseData)
            apduResponse.append(swChar, count: 2)
            
            waitSemaphore.signal()
        } else {
            waitSemaphore.signal()
        }
    }
    
    let waitResponse = waitSemaphore.wait(timeout: DispatchTime.now() + 13.0)
    
    if waitResponse != .success {
        return blueAsClibReturnCode(.timeout)
    }
    
    do {
        _ = try blueCopyDataToClib(data: apduResponse, buffer: pResponseApdu, bufferSize: pResponseApduLength.pointee)
        pResponseApduLength.pointee = UInt32(apduResponse.count)
    } catch let error {
        blueLogError(error.localizedDescription)
        return blueAsClibReturnCode(.error)
    }
    
    return blueAsClibReturnCode(.ok)
}

#else

internal func blueNfcExecute(_ handler: @escaping (_: BlueTransponderType) throws -> String, timeoutSeconds: Double = 0) throws {
    throw BlueError(.notSupported)
}

@_cdecl("blueNfc_Transceive")
internal func blueNfc_Transceive(_ pCommandApdu: UnsafePointer<UInt8>, _ commandApduLength: UInt32, _ pResponseApdu: UnsafeMutablePointer<UInt8>, _ pResponseApduLength: UnsafeMutablePointer<UInt32>) -> BlueReturnCode_t {
    return blueAsClibReturnCode(.notSupported)
}

#endif
