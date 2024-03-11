import Foundation
import Combine

internal struct BlueCredentialPushEventPair {
    let credentialID: String
    let event: BluePushEvent
}

internal class BlueAccessEventService: BlueAccessEventServiceProtocol {
    private let MAX_EVENTS = 100
    
    private let apiService: BlueAPIProtocol
    private let networkMonitorService: BlueNetworkMonitorService
    private var networkSubscriber: AnyCancellable?
    
    private var events: [BlueCredentialPushEventPair] = []
    private var eventsQueue = DispatchQueue(label: "blueid.events", qos: .background, attributes: .concurrent)
    
    init(_ apiService: BlueAPIProtocol, _ networkMonitorService: BlueNetworkMonitorService) {
        self.apiService = apiService
        self.networkMonitorService = networkMonitorService
        
        self.networkSubscriber = self.networkMonitorService.networkStatus
            .sink { _ in
                self.eventsQueue.async {
                    Task {
                        await self.flush()
                    }
                }
            }
    }
    
    func pushEvents(_ credentialID: String, _ newEvents: [BluePushEvent]) {
        eventsQueue.async(flags: .barrier) {
            Task {
                self.events.append(contentsOf: newEvents.map{ BlueCredentialPushEventPair(credentialID: credentialID, event: $0) })
                
                if (self.events.count > self.MAX_EVENTS) {
                    blueLogWarn("Events overflowed, only last \(self.MAX_EVENTS) events will be kept")
                    
                    self.events = self.events.suffix(self.MAX_EVENTS)
                }
                
                await self.flush()
            }
        }
    }
    
    private func flush() async {
        guard networkMonitorService.isConnected() else {
            blueLogInfo("No internet connection, events will be pushed once there is a connection")
            return
        }
        
        guard !self.events.isEmpty else {
            blueLogInfo("No events to be pushed")
            return
        }

        let events: [BlueCredentialPushEventPair] = Array(self.events)
        
        self.events.removeAll()
        
        let chunks = events.reduce(into: [String: [BluePushEvent]]()) { result, element in
            result[element.credentialID, default: []].append(element.event)
        }
        
        await withTaskGroup(of: Void.self) { group in
            for chunk in chunks {
                group.addTask { await self.handleChunk(chunk) }
            }
        }
    }
    
    private func handleChunk(_ chunk: (key: String, value: [BluePushEvent])) async {
        do {
            guard let credential = blueGetAccessCredential(credentialID: chunk.key) else {
                blueLogWarn("Credential not found")
                return
            }
            
            // /access/pushEvents can only handle 50 events
            let subchunks = chunk.value.chunks(of: 50)
            
            for subchunk in subchunks {
                let tokenAuthentication = try await BlueAccessAPIHelper(apiService).getTokenAuthentication(credential: credential)
                
                let result = try await apiService.pushEvents(events: subchunk, with: tokenAuthentication).getData()
                
                if (result.storedEvents.count != subchunk.count) {
                    blueLogWarn("Some events have not been deployed")
                }
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
}
