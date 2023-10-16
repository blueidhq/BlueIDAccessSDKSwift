import Foundation
import CBlueIDAccess

private typealias BlueSPReceivedFunc = @convention(c) () -> BlueReturnCode_t
private typealias BlueSPReceiveFinishFunc = @convention(c) () -> BlueReturnCode_t

private typealias BlueSPConnectionVtable_getMaxFrameSize = @convention(c) (UnsafeMutableRawPointer?) -> UInt16
private typealias BlueSPConnectionVtable_hasFinishCallback = @convention(c) (UnsafeMutableRawPointer?) -> Bool
private typealias BlueSPConnectionVtable_transmit = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UInt16) -> BlueReturnCode_t
private typealias BlueSPConnectionVtable_receive = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UInt16, UnsafeMutablePointer<UInt16>?, BlueSPReceivedFunc?, BlueSPReceiveFinishFunc?) -> BlueReturnCode_t

private let spConnectionCallback_getMaxFrameSize: BlueSPConnectionVtable_getMaxFrameSize = { context in
    guard let context = context else { return 0 }
    
    let spConnection : BlueSPConnection = Unmanaged.fromOpaque(context).takeUnretainedValue()
    
    return spConnection.getMaxFrameSize()
}

private let spConnectionCallback_hasFinishCallback: BlueSPConnectionVtable_hasFinishCallback = { context in
    return false
}

private let spConnectionCallback_transmit: BlueSPConnectionVtable_transmit = { context, txBuffer, txBufferSize in
    guard let context = context, let txBuffer = txBuffer else { return blueAsClibReturnCode(.invalidArguments) }
    
    let spConnection : BlueSPConnection = Unmanaged.fromOpaque(context).takeUnretainedValue()
    
    do
    {
        let txData = try blueCopyDataFromClib(buffer: txBuffer, bufferSize: UInt32(txBufferSize))
        try spConnection.transmit(txData: txData)
        return blueAsClibReturnCode(.ok)
    } catch let error as BlueError {
        return blueAsClibReturnCode(error.returnCode)
    } catch {
        return blueAsClibReturnCode(.invalidArguments)
    }
}

private let spConnectionCallback_receive: BlueSPConnectionVtable_receive = { context, rxBuffer, rxBufferSize, rxReturnedSize, receiveCallback, finishedCallback in
    guard let context = context, let rxBuffer = rxBuffer, let rxReturnedSize = rxReturnedSize else { return blueAsClibReturnCode(.invalidArguments) }
    
    let spConnection : BlueSPConnection = Unmanaged.fromOpaque(context).takeUnretainedValue()
    
    do
    {
        let rxData = try spConnection.receive()
        
        guard let rxData = rxData else {
            return blueAsClibReturnCode(.invalidState)
        }
        
        if (rxData.isEmpty) {
            throw BlueError(.eof)
        }
        
        try blueCopyDataToClib(data: rxData, buffer: rxBuffer, bufferSize: UInt32(rxBufferSize))
        rxReturnedSize.pointee = UInt16(rxData.count)
        return blueAsClibReturnCode(.ok)
    } catch let error as BlueError {
        return blueAsClibReturnCode(error.returnCode)
    } catch {
        return blueAsClibReturnCode(.invalidArguments)
    }
}

internal protocol BlueSPConnectionDelegate {
    func getMaxFrameSize() -> UInt16
    func transmit(txData: Data) throws
    func receive() throws -> Data?
}

internal class BlueSPConnection {
    private let connectionVTablePtr: UnsafeMutablePointer<BlueSPConnectionVtable_t>
    private let connectionVTablePtrConst: UnsafePointer<BlueSPConnectionVtable_t>
    
    internal let connectionPtr: UnsafeMutablePointer<BlueSPConnection_t>
    
    internal var delegate: BlueSPConnectionDelegate? = nil
    
    public init() {
        connectionVTablePtr = UnsafeMutablePointer<BlueSPConnectionVtable_t>.allocate(capacity: 1)
        connectionVTablePtr.pointee.getMaxFrameSize = spConnectionCallback_getMaxFrameSize
        connectionVTablePtr.pointee.hasFinishCallback = spConnectionCallback_hasFinishCallback
        connectionVTablePtr.pointee.transmit = spConnectionCallback_transmit
        connectionVTablePtr.pointee.receive = spConnectionCallback_receive
        
        connectionVTablePtrConst = UnsafePointer<BlueSPConnectionVtable_t>(connectionVTablePtr)
        
        connectionPtr = UnsafeMutablePointer<BlueSPConnection_t>.allocate(capacity: 1)
        connectionPtr.pointee.pContext = Unmanaged.passUnretained(self).toOpaque()
        connectionPtr.pointee.pFuncs = connectionVTablePtrConst
    }
    
    deinit {
        connectionPtr.deallocate()
        connectionVTablePtr.deallocate()
    }
    
    fileprivate func getMaxFrameSize() -> UInt16 {
        if let delegate = self.delegate {
            return delegate.getMaxFrameSize()
        }
        
        return 0
    }
    
    fileprivate func transmit(txData: Data) throws {
        if let delegate = self.delegate {
            try delegate.transmit(txData: txData)
        } else {
            throw BlueError(.invalidState)
        }
    }
    
    fileprivate func receive() throws -> Data? {
        if let delegate = self.delegate {
            return try delegate.receive()
        } else {
            throw BlueError(.invalidState)
        }
    }
}
