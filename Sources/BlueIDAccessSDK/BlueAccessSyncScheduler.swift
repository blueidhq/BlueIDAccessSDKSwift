import Foundation

private class ForegroundScheduler {
    private var timer: Timer?
    private var scheduler: BlueAccessSyncScheduler?
    
    func setup(_ scheduler: BlueAccessSyncScheduler) {
        self.scheduler = scheduler
    }
    
    func suspend() {
        timer?.invalidate()
        timer = nil
    }
    
    func schedule(_ now: Bool? = false) {
        suspend()
        
        if now == true {
            self.handleTask()
        } else {
            blueRunInMainThread {
                self.timer = Timer.scheduledTimer(
                    timeInterval: self.scheduler!.calculateNextInterval(),
                    target: self,
                    selector: #selector(self.handleTask),
                    userInfo: nil,
                    repeats: false
                )
            }
        }
    }
    
    @objc private func handleTask() {
        DispatchQueue.global(qos: .background).async {
            Task {
                do {
                    try await self.scheduler!.synchronizeAccessCredentials()
                } catch {
                    blueLogError(error.localizedDescription)
                }
                
                if (self.scheduler!.autoSchedule) {
                    self.schedule()
                }
            }
        }
    }
}

internal class BlueAccessSyncScheduler: BlueEventListener {
    public static let shared = BlueAccessSyncScheduler()
    
    let timeInterval: TimeInterval
    let autoSchedule: Bool
    
    private let foregroundScheduler = ForegroundScheduler()
    
    private let command: BlueSynchronizeAccessCredentialsCommand
    
    private var syncing = false
    
    init(
        timeInterval: TimeInterval? = 60 * 60 * 6, // every 6h by default
        autoSchedule: Bool? = true,
        command: BlueSynchronizeAccessCredentialsCommand? = nil
    ) {
        self.command = command ?? blueCommands.synchronizeAccessCredentials
        self.timeInterval = timeInterval ?? 60
        self.autoSchedule = autoSchedule ?? true
        
        foregroundScheduler.setup(self)
        
        blueAddEventListener(listener: self)
    }
    
    deinit {
        blueRemoveEventListener(listener: self)
    }
    
    func willResignActive() {
        suspend()
    }
    
    func willTerminate() {
        suspend()
    }
    
    func didBecomeActive() {
        schedule(true)
    }
    
    func didFinishLaunching() {
        schedule(true)
    }
    
    func blueEvent(event: BlueEventType, data: Any?) {
        if (event == .accessCredentialAdded) {
            schedule()
        }
    }
    
    func schedule(_ now: Bool? = false) {
        do {
            guard try blueAccessCredentialsKeyChain.getNumberOfEntries() > 0 else {
                return
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
        
        foregroundScheduler.schedule(now)
    }
    
    func suspend() {
        foregroundScheduler.suspend()
    }
    
    func synchronizeAccessCredentials() async throws -> Void {
        if (syncing) {
            blueLogInfo("There is already a synchronization in progress")
            return
        }
        
        syncing = true
        
        blueFireListeners(fireEvent: BlueEventType.tokenSyncStarted, data: nil)
        
        defer {
            syncing = false
            
            blueFireListeners(fireEvent: BlueEventType.tokenSyncFinished, data: nil)
        }
        
        _ = try await command.runAsync()
    }
    
    func calculateNextInterval(_ now: Date? = nil) -> TimeInterval {
        var interval: TimeInterval = self.timeInterval
        
        if let credentials = try? blueCommands.getAccessCredentials.run().credentials {
            if (!credentials.isEmpty) {
                credentials.forEach { credential in
                    let now = now ?? Date()
                    
                    if (!credential.checkValidityStart(now)) {
                        if let validFrom = credential.validFrom.toUTCDate() {
                            if validFrom > now {
                                let differenceInSeconds = validFrom.timeIntervalSince(now)
                                
                                interval = min(differenceInSeconds, interval)
                            }
                        }
                    }
                }
            }
        }
        
        return interval
    }
}
