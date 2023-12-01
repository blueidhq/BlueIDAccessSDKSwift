import Foundation

internal class BlueStorage {
    let collection: String
    
    init(collection: String) {
        self.collection = collection
    }
    
    func storeCodableEntry(key: String, data: Codable) throws -> Void{
        self.storeEntry(key: key, data: try JSONEncoder().encode(data))
    }

    func getCodableEntry<T>(key: String) throws -> T? where T: Codable {
        if let entry = self.getEntry(key: key) {
            return try JSONDecoder().decode(T.self, from: entry)
        }
        
        return nil
    }
    
    func deleteAllEntries() {
        BlueStorage.deleteAllEntries(collection: self.collection)
    }
    
    func storeEntry(key: String, data: Data) {
        BlueStorage.storeEntry(collection: self.collection, key: key, data: data)
    }
    
    func getEntry(key: String) -> Data? {
        return BlueStorage.getEntry(collection: self.collection, key: key)
    }
    
    static func storeEntry(collection: String, key: String, data: Data) {
        UserDefaults.standard.set(data, forKey: "\(collection).\(key)")
    }
    
    static func getEntry(collection: String, key: String) -> Data? {
        return UserDefaults.standard.data(forKey: "\(collection).\(key)")
    }
    
    static func deleteAllEntries(collection: String) {
        for (key, _) in UserDefaults.standard.dictionaryRepresentation() {
            if key.hasPrefix(collection) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
