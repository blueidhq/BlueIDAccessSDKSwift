//
//  BlueTokenSyncScheduler.swift
//
//  Description: Synchronize all tokens from all available credentials at specific intervals.
//
//  If you would like to test the background task during development, execute the following code in the console:
//  ```
//  e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.blue-id.BlueTokenSyncScheduler"]
//  ```
//
//  Reference: https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development#Launch-a-Task
//
//  Copyright © 2023 BlueID. All rights reserved.
//

import Foundation

private let bgTaskIdentifier = "com.blue-id.BlueTokenSyncScheduler"

private class ForegroundScheduler {
    private var timer: Timer?
    private var scheduler: BlueTokenSyncScheduler?
    
    func setup(_ scheduler: BlueTokenSyncScheduler) {
        self.scheduler = scheduler
    }
    
    func suspend() {
        timer?.invalidate()
        timer = nil
    }
    
    func schedule() {
        suspend()
        
        if (Thread.isMainThread) {
            scheduleTimer()
        } else {
            DispatchQueue.main.async {
                self.scheduleTimer()
            }
        }
    }
    
    private func scheduleTimer() {
        timer = Timer.scheduledTimer(
            timeInterval: scheduler!.timeInterval,
            target: self,
            selector: #selector(handleTask),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc private func handleTask() {
        if #available(macOS 10.15, *) {
            Task {
                do {
                    try await scheduler!.syncTokens()
                } catch {
                    blueLogError("Tokens could not be synchronized")
                }
                
                if (scheduler!.autoSchedule) {
                    schedule()
                }
            }
        } else {
            blueLogWarn("Unsupported version")
        }
    }
}


#if os(iOS) || os(watchOS)
import BackgroundTasks

private class BackgroundScheduler {
    private var scheduler: BlueTokenSyncScheduler?
    
    func setup(_ scheduler: BlueTokenSyncScheduler) {
        self.scheduler = scheduler
    }
    
    func registerIdentifiers() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: DispatchQueue.global()) { task in
            self.handleTask(task: task as! BGProcessingTask)
        }
        
        if (!registered) {
            blueLogWarn("Could not register background task identifier: \(bgTaskIdentifier)")
            return
        }
        
        blueLogDebug("Background task identifier has been successfully registered: \(bgTaskIdentifier)")
    }
    
    func suspend() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
    }
    
    func schedule() {
        do {
            let request = BGProcessingTaskRequest(identifier: bgTaskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: scheduler!.timeInterval)
            request.requiresNetworkConnectivity = true
            
            try BGTaskScheduler.shared.submit(request)
            
            blueLogDebug("Background task has been successfully scheduled")
        } catch {
            blueLogError("Background task could not be scheduled: \(error)")
        }
    }
    
    private func handleTask(task: BGProcessingTask) -> Void {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                try await scheduler!.syncTokens()
                
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
            
            if (scheduler!.autoSchedule) {
                schedule()
            }
        }
    }
}
#endif

internal class BlueTokenSyncScheduler: BlueEventListener {
    public static let shared = BlueTokenSyncScheduler()
    
    let timeInterval: TimeInterval
    let autoSchedule: Bool
    
    #if os(iOS) || os(watchOS)
    private let backgroundScheduler = BackgroundScheduler()
    #endif
    
    private let foregroundScheduler = ForegroundScheduler()
    
    private let command: BlueSynchronizeAccessCredentialCommand
    
    init(
        timeInterval: TimeInterval? = 60,
        autoSchedule: Bool? = true,
        command: BlueSynchronizeAccessCredentialCommand? = nil
    ) {
        self.command = command ?? blueCommands.synchronizeAccessCredential
        self.timeInterval = timeInterval ?? 60
        self.autoSchedule = autoSchedule ?? true
        
        foregroundScheduler.setup(self)
        
        #if os(iOS) || os(watchOS)
        backgroundScheduler.setup(self)
        #endif
        
        blueAddEventListener(listener: self)
    }
    
    deinit {
        blueRemoveEventListener(listener: self)
    }
    
    func willResignActive() {
        foregroundScheduler.suspend()
        
        #if os(iOS) || os(watchOS)
        backgroundScheduler.schedule()
        #endif
    }

    func didBecomeActive() {
        #if os(iOS) || os(watchOS)
        backgroundScheduler.suspend()
        #endif
        
        foregroundScheduler.schedule()
    }

    func didFinishLaunching() {
        setup()
    }

    func willTerminate() {
        suspend()
    }
    
    func blueEvent(event: BlueEventType, data: Any?) {
        if (event == .accessCredentialAdded) {
            schedule()
        }
    }
    
    func setup() {
        #if os(iOS)
        backgroundScheduler.registerIdentifiers()
        #endif

        schedule()
    }
    
    func schedule() {
        do {
            guard try blueAccessCredentialsKeyChain.getNumberOfEntries() > 0 else {
                return
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
        
        blueRemoveEventListener(listener: self)

        foregroundScheduler.schedule()
    }
    
    func suspend() {
        foregroundScheduler.suspend()
        
        #if os(iOS) || os(watchOS)
        backgroundScheduler.suspend()
        #endif
    }
    
    @available(macOS 10.15, *)
    func syncTokens() async throws -> Void {
        blueFireListeners(fireEvent: BlueEventType.tokenSyncStarted, data: nil)
        
        defer {
            blueFireListeners(fireEvent: BlueEventType.tokenSyncFinished, data: nil)
        }
        
        let accessCredentialList = try await blueCommands.getAccessCredentials.runAsync()

        await withThrowingTaskGroup(of: Void.self) { group in
            for credential in accessCredentialList.credentials {
                group.addTask {
                    do {
                        try await self.command.runAsync(credentialID: credential.credentialID.id)
                        
                        blueLogDebug("Access credential has been successfully synchronized: \(credential.credentialID.id)")
                    } catch {
                        blueLogError("Access credential could not be synchronized: \(error)")
                    }
                }
            }
        }
    }
}
