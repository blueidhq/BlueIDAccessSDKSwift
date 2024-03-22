import Foundation

/**
 * @class BlueZip
 * A utility class for working with zip files.
 */
public class BlueZip {
    /// Extracts contents of a zip file from the provided Data object.
    ///
    /// - parameter data: The Data object representing the zip file.
    /// - returns: URL pointing to the location where the contents of the zip file are extracted.
    /// - throws: An error if the extraction process encounters any issues.
    static func extract(data: Data) throws -> URL {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let sourceURL = tempDirectoryURL.appendingPathComponent("package.zip")
        let destinationURL = tempDirectoryURL.appendingPathComponent("extracted_package")
        
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try data.write(to: sourceURL)

        try fileManager.unzipItem(at: sourceURL, to: destinationURL)
        
        return destinationURL
    }
}
