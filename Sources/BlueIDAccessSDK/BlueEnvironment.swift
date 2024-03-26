import Foundation

/**
 * @class BlueEnvironment
 * This class provides access to environment-specific configurations and settings related to the SDK environment.
 */
internal class BlueEnvironment {
    /// Gets the value of an environment variable.
    ///
    /// - parameters:
    ///   - key: The key of the environment variable.
    ///   - defaultValue: The default value to return if the environment variable is not found.
    /// - returns: The value of the environment variable if found, otherwise the defaultValue.
    static func getEnvVar(key: String, defaultValue: String) -> String {
        guard let infoDictionary: [String: Any] = Bundle.main.infoDictionary else { return defaultValue }
        
        guard let value: String = infoDictionary[key] as? String else { return defaultValue }
        
        return value
    }
}
