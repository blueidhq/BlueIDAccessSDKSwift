import XCTest

@testable import BlueIDAccessSDK

final class BlueSignatureTests: BlueXCTestCase {
    
    func testCreateSignature() async throws {
        let inputData = "token".data(using: .utf8)!
        let privateKey = Data([48,129,135,2,1,0,48,19,6,7,42,134,72,206,61,2,1,6,8,42,134,72,206,61,3,1,7,4,109,48,107,2,1,1,4,32,152,140,1,4,26,171,230,250,50,58,133,42,72,22,74,103,101,4,52,190,56,249,13,177,58,239,59,152,24,77,206,70,161,68,3,66,0,4,20,157,192,46,230,76,158,83,178,64,1,123,2,215,50,237,229,179,163,90,65,21,151,138,176,247,72,158,170,236,93,84,40,38,57,18,121,60,215,228,21,16,242,30,21,101,248,90,139,31,61,150,198,4,196,146,96,174,92,230,194,140,79,9])
        
        let signature = try createSignature(inputData: inputData, privateKey: privateKey)
        
        XCTAssertNotNil(signature, "Signature should not be null")
    }
}
