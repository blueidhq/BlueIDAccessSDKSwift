import Foundation

internal class BlueStorage {
    let collection: String
    
    init(collection: String) {
        self.collection = collection
    }
    
    func storeCodableEntry(id: String, data: Codable) throws -> Void{
        self.storeEntry(id: id, data: try JSONEncoder().encode(data))
    }

    func getCodableEntry<T>(id: String) throws -> T? where T: Codable {
        if let entry = self.getEntry(id: id) {
            return try JSONDecoder().decode(T.self, from: entry)
        }
        
        return nil
    }
    
    func deleteAllEntries() {
        BlueStorage.deleteAllEntries(collection: self.collection)
    }
    
    func deleteEntry(id: String) {
        BlueStorage.deleteEntry(collection: self.collection, id: id)
    }
    
    func storeEntry(id: String, data: Data) {
        BlueStorage.storeEntry(collection: self.collection, id: id, data: data)
    }
    
    func getEntry(id: String) -> Data? {
        return BlueStorage.getEntry(collection: self.collection, id: id)
    }
    
    static func storeEntry(collection: String, id: String, data: Data) {
        UserDefaults.standard.set(data, forKey: "\(collection).\(id)")
    }
    
    static func deleteEntry(collection: String, id: String) {
        UserDefaults.standard.removeObject(forKey: "\(collection).\(id)")
    }
    
    static func getEntry(collection: String, id: String) -> Data? {
        return UserDefaults.standard.data(forKey: "\(collection).\(id)")
    }
    
    static func deleteAllEntries(collection: String) {
        for (key, _) in UserDefaults.standard.dictionaryRepresentation() {
            if key.hasPrefix(collection) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
