import Foundation

extension BlueLocalTimestamp: Encodable, Decodable {
    public init(_ date: Date) {
        self.init()
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        
        self.year = UInt32(components.year!)
        self.month = UInt32(components.month!)
        self.date = UInt32(components.day!)
        self.hours = UInt32(components.hour!)
        self.minutes = UInt32(components.minute!)
        self.seconds = UInt32(components.second!)
    }
    
    public init(_ year: Int, _ month: Int, _ date: Int = 1, _ hours: Int = 0, _ minutes: Int = 0, _ seconds: Int = 0) {
        self.init()
        
        self.year = UInt32(year)
        self.month = UInt32(month)
        self.date = UInt32(date)
        self.hours = UInt32(hours)
        self.minutes = UInt32(minutes)
        self.seconds = UInt32(seconds)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        year = try container.decode(UInt32.self, forKey: .year)
        month = try container.decode(UInt32.self, forKey: .month)
        date = try container.decode(UInt32.self, forKey: .date)
        hours = try container.decode(UInt32.self, forKey: .hours)
        minutes = try container.decode(UInt32.self, forKey: .minutes)
        seconds = try container.decode(UInt32.self, forKey: .seconds)
    }
    
    public func toDate() -> Date? {
        var dateComponents = DateComponents()
        dateComponents.year = Int(year)
        dateComponents.month = Int(month)
        dateComponents.day = Int(date)
        dateComponents.hour = Int(hours)
        dateComponents.minute = Int(minutes)
        dateComponents.second = Int(seconds)
        
        let date = Calendar.current.date(from: dateComponents)
        if (date?.timeIntervalSince1970 ?? 0 <= 0) {
            return nil
        }
        
        return date
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(date, forKey: .date)
        try container.encode(hours, forKey: .hours)
        try container.encode(minutes, forKey: .minutes)
    }
    
    enum CodingKeys: String, CodingKey {
        case year
        case month
        case date
        case hours
        case minutes
        case seconds
    }
}

extension BlueAccessObject: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: ._id)
        objectID = try container.decode(Int32.self, forKey: .objectId)
        name = try container.decode(String.self, forKey: .name)
        
        if let description = try? container.decode(String.self, forKey: .description) {
            description_p = description
        }
        
        if let deviceIds = try? container.decode([String].self, forKey: .deviceIds) {
            self.deviceIds = deviceIds
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case _id
        case objectId
        case name
        case description
        case deviceIds
    }
}

extension BlueAccessCredential: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        credentialID = BlueCredentialId()
        credentialID.id = try container.decode(String.self, forKey: .credentialId)
        
        let credentialTypeAsString = try container.decode(String.self, forKey: .credentialType)
        guard let credentialType = BlueCredentialType(stringValue: credentialTypeAsString) else {
            throw BlueError(.invalidState)
        }
        
        self.credentialType = credentialType
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? String()
        self.description_p = try container.decodeIfPresent(String.self, forKey: .description) ?? String()
        self.validFrom = try container.decodeIfPresent(BlueLocalTimestamp.self, forKey: .validFrom) ?? BlueLocalTimestamp()
        self.validTo = try container.decodeIfPresent(BlueLocalTimestamp.self, forKey: .validTo) ?? BlueLocalTimestamp()
        self.validity = try container.decodeIfPresent(BlueLocalTimestamp.self, forKey: .validity) ?? BlueLocalTimestamp()
        self.siteID = try container.decode(Int32.self, forKey: .siteId)
        self.siteName = try container.decodeIfPresent(String.self, forKey: .siteName) ?? String()
        self.receiverName = try container.decodeIfPresent(String.self, forKey: .receiverName) ?? String()
        self.organisation = try container.decode(String.self, forKey: .organisation)
        self.organisationName = try container.decodeIfPresent(String.self, forKey: .organisationName) ?? String()
        
        if let privateKeyBase64 = try container.decodeIfPresent(String.self, forKey: .privateKey) {
            if let privateKey = Data(base64Encoded: privateKeyBase64) {
                self.privateKey = privateKey
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case credentialId
        case credentialType
        case validFrom
        case validTo
        case validity
        case privateKey
        case siteId
        case siteName
        case receiverName
        case organisation
        case organisationName
    }
}

extension BlueCredentialType {
    init?(stringValue: String) {
        switch stringValue.lowercased() {
            case "regular":
                self = .regular
            case "maintenance":
                self = .maintenance
            case "master":
                self = .master
            case "nfcwriter":
                self = .nfcWriter
            default:
                return nil
        }
    }
}

extension BlueAccessCredentialList {
    public init (credentials: [BlueAccessCredential]) {
        self.credentials = credentials
    }
}

extension BlueAccessObjectList {
    public init (objects: [BlueAccessObject]) {
        self.objects = objects
    }
}

extension BlueAccessDeviceList {
    public init(devices: [BlueAccessDevice]) {
        self.devices = devices
    }
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        var index = 0
        var result = [[Element]]()
        
        while index < self.count {
            let endIndex = index + size < self.count ? index + size : self.count
            let subArray = Array(self[index..<endIndex])
            result.append(subArray)
            index += size
        }
        
        return result
    }
}

