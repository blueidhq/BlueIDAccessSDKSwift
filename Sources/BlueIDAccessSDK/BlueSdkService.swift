
struct BlueSdkService {
    let apiService: BlueAPIProtocol
    let eventService: BlueAccessEventServiceProtocol
    
    init(_ apiService: BlueAPIProtocol, _ eventService: BlueAccessEventServiceProtocol) {
        self.apiService = apiService
        self.eventService = eventService
    }
    
    var authenticationTokenService: BlueAccessAPIHelper {
        return BlueAccessAPIHelper(apiService)
    }
    
    var ossSoService: BlueOssSoAPIHelper {
        return BlueOssSoAPIHelper(apiService)
    }
}
