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
    var rawData: Data? = nil
    
    func getData() throws -> T {
        guard let data = data else {
            if let rawData = rawData as? T {
                return rawData
            }
            
            let status: String = statusCode?.description ?? "Unknown"
            var description = ""
            
            if let rawData = rawData {
                if (!rawData.isEmpty) {
                    if let text = String(data: rawData, encoding: .utf8) {
                        description = " (\(text))"
                    }
                }
            }
            
            throw BlueError(
                .sdkFetchDataFailed,
                cause: NSError(
                    domain: "BlueID",
                    code: BlueReturnCode.sdkFetchDataFailed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(status)\(description)"]
                )
            )
        }
        
        return data
    }
}

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
        var contentType: String?
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                statusCode = httpResponse.statusCode
                contentType = httpResponse.value(forHTTPHeaderField: "content-type")
                
                blueLogDebug("Status code: \(httpResponse.statusCode)")
                blueLogDebug("Content-Type: \(String(describing: contentType))")
                blueLogDebug("Data: \(String(describing: String(data: data, encoding: .utf8)))")
            }
            
            let isJSON = contentType == "application/json"
            
            if (statusCode == 200 && isJSON) {
                do {
                    decodedData = try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw BlueError(.sdkDecodeJsonFailed, cause: error)
                }
            }
            
            return BlueFetchResponse(statusCode: statusCode, data: decodedData, rawData: data)
        } catch {
            throw BlueError(.sdkNetworkError, cause: error)
        }
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

