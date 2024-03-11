import Network
import Combine

internal final class BlueNetworkMonitorService {
    let networkStatus = PassthroughSubject<Bool, Never>()

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "blueid.network-monitor")
    
    private var connected: Bool = false

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            self.connected = path.status == .satisfied
            self.networkStatus.send(self.connected)
        }
        
        pathMonitor.start(queue: pathMonitorQueue)
    }
    
    func isConnected() -> Bool {
        return connected
    }
}
