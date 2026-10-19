import Foundation
import SyncCore

/// Records requests and answers them from a script.
public actor StubHTTPClient: HTTPClient {
    public private(set) var requests: [HTTPRequest] = []
    private var responses: [Result<HTTPResponse, RemoteError>]

    public init(responses: [Result<HTTPResponse, RemoteError>]) {
        self.responses = responses
    }

    public func send(_ request: HTTPRequest) async throws(RemoteError) -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw .malformedResponse("no scripted response left")
        }
        return try responses.removeFirst().get()
    }

    public static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> Result<HTTPResponse, RemoteError> {
        .success(HTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { first, _ in first }, body: Data(body.utf8)))
    }
}
