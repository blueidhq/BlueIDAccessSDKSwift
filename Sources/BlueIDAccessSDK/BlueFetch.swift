import Foundation

struct BlueFetchConfig {
    var headers: [String: String]?
    
    init(headers: [String : String]? = nil) {
        self.headers = headers
    }
}

@available(macOS 12.0, *)
class BlueFetch {
    static func post<T>(url: URL, data: Data?, config: BlueFetchConfig? = nil) async throws -> T where T: Decodable {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        
        self.applyConfig(&request, config)
        return try await self.fetch(with: request)
    }
    
    static func get<T>(url: URL, config: BlueFetchConfig? = nil) async throws -> T where T: Decodable {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        self.applyConfig(&request, config)
        return try await self.fetch(with: request)
    }
    
    static func fetch<T>(with request: URLRequest) async throws -> T where T: Decodable {
        blueLogDebug("[\(BlueFetch.self)] \(request.httpMethod ?? "") \(String(describing: request.url))")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            blueLogDebug("[\(BlueFetch.self)] Status code: \(httpResponse.statusCode)")
            blueLogDebug("[\(BlueFetch.self)] Data: \(String(describing: String(data: data, encoding: .utf8)))")
        }
        
        let decodedData = try JSONDecoder().decode(T.self, from: data)
        
        return decodedData
    }
    
    private static func applyConfig(_ request: inout URLRequest, _ config: BlueFetchConfig?) {
        guard let config = config else {
            return
        }
        
        if let headers = config.headers {
            headers.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
    }
}

