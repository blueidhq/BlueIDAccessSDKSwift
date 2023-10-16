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
}

