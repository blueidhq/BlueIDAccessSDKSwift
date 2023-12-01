import Foundation

extension BlueLocalTimestamp {
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
}
