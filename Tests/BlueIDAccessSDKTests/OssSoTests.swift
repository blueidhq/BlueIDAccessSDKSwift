import XCTest

@testable import BlueIDAccessSDK

final class OssSoTests: XCTestCase {
    func testGetStorageProfile() throws {
        // Test with default profile
        let defaultProfile = try BlueOssSoGetStorageProfileCommand().run(.mifareDesfire, nil)
        
        XCTAssertEqual(defaultProfile.infoDataLength, 32)
        
        XCTAssertEqual(defaultProfile.infoFileSize, 32)
        XCTAssertEqual(defaultProfile.dataDataLength, 262)
        XCTAssertEqual(defaultProfile.dataFileSize, 288)
        XCTAssertEqual(defaultProfile.eventDataLength, 165)
        XCTAssertEqual(defaultProfile.eventFileSize, 192)
        XCTAssertEqual(defaultProfile.blacklistDataLength, 49)
        XCTAssertEqual(defaultProfile.blacklistFileSize, 64)
        XCTAssertEqual(defaultProfile.customerExtensionsDataLength, 18)
        XCTAssertEqual(defaultProfile.customerExtensionsFileSize, 32)
        XCTAssertEqual(defaultProfile.dataLength, 526)
        XCTAssertEqual(defaultProfile.fileSize, 608)
        
        // Test with general profile
        var provisioningConfig = BlueOssSoProvisioningConfiguration()
        provisioningConfig.numberOfDoors = 255
        provisioningConfig.numberOfDtschedules = 15
        provisioningConfig.numberOfDayIdsPerDtschedule = 4
        provisioningConfig.numberOfTimePeriodsPerDayID = 4
        provisioningConfig.numberOfEvents = 0
        provisioningConfig.supportedEventIds = Data()
        provisioningConfig.numberOfBlacklistEntries = 0
        provisioningConfig.customerExtensionsSize = 16
        
        let generalProfile = try BlueOssSoGetStorageProfileCommand().run(.mifareDesfire, provisioningConfig)
        
        XCTAssertEqual(generalProfile.infoDataLength, 32)
        XCTAssertEqual(generalProfile.infoFileSize, 32)
        XCTAssertEqual(generalProfile.dataDataLength, 1801)
        XCTAssertEqual(generalProfile.dataFileSize, 1824)
        XCTAssertEqual(generalProfile.eventDataLength, 0)
        XCTAssertEqual(generalProfile.eventFileSize, 0)
        XCTAssertEqual(generalProfile.blacklistDataLength, 0)
        XCTAssertEqual(generalProfile.blacklistFileSize, 0)
        XCTAssertEqual(generalProfile.customerExtensionsDataLength, 18)
        XCTAssertEqual(generalProfile.customerExtensionsFileSize, 32)
        XCTAssertEqual(generalProfile.dataLength, 1851)
        XCTAssertEqual(generalProfile.fileSize, 1888)
    }
}
