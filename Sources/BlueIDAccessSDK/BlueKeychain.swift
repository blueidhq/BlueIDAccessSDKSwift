import Foundation
import Security

internal class BlueKeychain {
    let attrService: String
    let attrAccessible: String
    
    public init(attrService: String!, attrAccessible: String? = nil) {
        self.attrService = attrService
        self.attrAccessible = attrAccessible ?? String(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }
    
    func getNumberOfEntries() throws -> Int {
        return try BlueKeychain.getNumberOfEntries(attrService: attrService)
    }
    
    func getEntryIds() throws -> [String] {
        return try BlueKeychain.getEntryIds(attrService: attrService)
    }
    
    func getEntry(id: String) throws -> Data? {
        return try BlueKeychain.getEntry(attrService: attrService, attrAccessible: attrAccessible, id: id)
    }
    
    func getAllEntries() throws -> [Data]? {
        return try BlueKeychain.getAllEntries(attrService: attrService, attrAccessible: attrAccessible)
    }
    
    func getCodableEntry<T>(id: String) throws -> T? where T: Codable {
        if let entry = try self.getEntry(id: id) {
            return try JSONDecoder().decode(T.self, from: entry)
        }
        return nil
    }
    
    func storeEntry(id: String, data: Data) throws {
        return try BlueKeychain.storeEntry(attrService: attrService, attrAccessible: attrAccessible, id: id, data: data)
    }
    
    func storeCodableEntry(id: String, data: Codable) throws {
        try self.storeEntry(id: id, data: try JSONEncoder().encode(data))
    }
    
    func deleteEntry(id: String) throws -> Bool {
        return try BlueKeychain.deleteEntry(attrService: attrService, id: id)
    }
    
    func deleteAllEntries() throws -> Int {
        return try BlueKeychain.deleteAllEntries(attrService: attrService)
    }
    
    //
    // -- Static implementations
    //
    static func getNumberOfEntries(attrService: String) throws -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if (status == errSecItemNotFound) {
            return 0
        }

        guard status == errSecSuccess else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }

        guard let attributes = result as? [[String: AnyObject]] else {
            throw BlueError(.invalidState)
        }

        return attributes.count
    }
    
    static func getEntryIds(attrService: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        
        if status == errSecSuccess {
            guard let items = items as? [[String: Any]] else {
                blueLogError("Keychain error \(status)")
                throw BlueError(.invalidState)
            }
            let ids = items.compactMap { $0[kSecAttrAccount as String] as? String }
            return ids
        } else if status == errSecItemNotFound {
            return []
        } else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }
    }
    
    static func getEntry(attrService: String, attrAccessible: String, id: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecAttrAccessible as String: attrAccessible,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            if let data = item as? Data {
                return data
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }
        
        return nil
    }
    
    static func getAllEntries(attrService: String, attrAccessible: String) throws -> [Data] {
        let entryIds = try getEntryIds(attrService: attrService)
        
        return try entryIds.compactMap{ try getEntry(attrService: attrService, attrAccessible: attrAccessible, id: $0) }
    }
    
    static func storeEntry(attrService: String, attrAccessible: String, id: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecAttrAccessible as String: attrAccessible,
            kSecAttrAccount as String: id,
            kSecValueData as String: data,
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        
        if status == errSecSuccess {
            // Noop all good
        } else if status == errSecItemNotFound {
            // Create item first time
            let createStatus = SecItemAdd(query as CFDictionary, nil)
            
            guard createStatus == errSecSuccess else {
                blueLogError("Keychain error \(createStatus)")
                throw BlueError(.invalidState)
            }
        } else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }
    }
    
    static func deleteEntry(attrService: String, id: String) throws -> Bool {
        // Define the query parameters
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecAttrAccount as String: id
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }
        
        return status == errSecSuccess
    }
    
    static func deleteAllEntries(attrService: String) throws -> Int {
        let numberOfEntries = try BlueKeychain.getNumberOfEntries(attrService: attrService)
        
        if (numberOfEntries == 0) {
            return numberOfEntries
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: attrService,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            blueLogError("Keychain error \(status)")
            throw BlueError(.invalidState)
        }
        
        return numberOfEntries
    }
}

