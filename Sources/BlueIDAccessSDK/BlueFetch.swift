import Foundation

struct BlueFetchConfig {
    var headers: [String: String]?
    
    init(headers: [String : String]? = nil) {
        self.headers = headers
    }
}

struct BlueFetchResponse<T> where T: Decodable {
    var statusCode: Int?
    var data: T?
    
    func getData() throws -> T {
        guard let data = data else {
            throw BlueError(.invalidState)
        }
        
        return data
    }
}

@available(macOS 12.0, *)
class BlueFetch {
    
    static func post<T>(url: URL, data: Data?, config: BlueFetchConfig? = nil) async throws -> BlueFetchResponse<T> where T: Decodable {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        
        self.applyConfig(&request, config ?? BlueFetchConfig(headers: ["Content-type": "application/json"]))
        return try await self.fetch(with: request)
    }
    
    static func get<T>(url: URL, config: BlueFetchConfig? = nil) async throws -> BlueFetchResponse<T> where T: Decodable {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        self.applyConfig(&request, config)
        return try await self.fetch(with: request)
    }
    
    static func fetch<T>(with request: URLRequest) async throws -> BlueFetchResponse<T> {
        blueLogDebug("\(request.httpMethod ?? "") \(String(describing: request.url))")
        
        var statusCode: Int?
        var decodedData: T?
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            
            blueLogDebug("Status code: \(httpResponse.statusCode)")
            blueLogDebug("Data: \(String(describing: String(data: data, encoding: .utf8)))")
        }
        
        if (statusCode == 200) {
            decodedData = try JSONDecoder().decode(T.self, from: data)
        }
        
        return BlueFetchResponse(statusCode: statusCode, data: decodedData)
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

