import XCTest

@testable import BlueIDAccessSDK

final class BlueGetAccessObjectsCommandTests: BlueXCTestCase {
    
    func testGetAccessObjects() async throws {
        class BlueAPIMock: DefaultBlueAPIMock {
            override func getAccessObjects(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessObjectsResult> {
                var object = BlueAccessObject()
                object.id = "id"
                object.objectID = 1
                object.name = "dummy"
                
                return BlueFetchResponse(
                    statusCode: 200,
                    data: [object]
                )
            }
        }
        
        let credential = blueCreateAccessCredentialDemo()
        let objectList = try? await BlueGetAccessObjectsCommand(BlueAPIMock()).runAsync(credential: credential)
        
        XCTAssertNotNil(objectList, "Returned objects should not be null")
        XCTAssertEqual(objectList?.objects.count, 1, "There should be 1 object")
        XCTAssertEqual(objectList?.objects[0].id, "id", "Wrong id")
        XCTAssertEqual(objectList?.objects[0].objectID, 1, "Wrong objectID")
        XCTAssertEqual(objectList?.objects[0].name, "dummy", "Wrong name")
    }
}
