import Foundation

public struct HTTPRequest: Sendable {
    public enum Body: Sendable, Hashable {
        case none
        case data(Data)
        case file(URL)
    }

    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Body
    public var timeout: Duration

    public init(method: String, url: URL, headers: [String: String], body: Body, timeout: Duration) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public let status: Int
    /// Header names in lowercase.
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws(RemoteError) -> HTTPResponse
}

/// `HTTPClient` over a dedicated ephemeral `URLSession`, never `URLSession.shared`.
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(requestTimeout: Duration = .seconds(30), resourceTimeout: Duration = .seconds(300)) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout.timeInterval
        configuration.timeoutIntervalForResource = resourceTimeout.timeInterval
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws(RemoteError) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout.timeInterval
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let data: Data
            let response: URLResponse
            switch request.body {
            case .none:
                (data, response) = try await session.data(for: urlRequest)
            case .data(let body):
                (data, response) = try await session.upload(for: urlRequest, from: body)
            case .file(let file):
                (data, response) = try await session.upload(for: urlRequest, fromFile: file)
            }
            guard let http = response as? HTTPURLResponse else {
                throw RemoteError.malformedResponse("response is not HTTP")
            }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                headers[String(describing: name)] = String(describing: value)
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as RemoteError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transient(status: nil, retryAfter: nil)
        }
    }

    public static func map(_ error: URLError) -> RemoteError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .fileDoesNotExist, .noPermissionsToReadFile:
            return .rejected(status: 0, reason: error.localizedDescription)
        default:
            return .transient(status: nil, retryAfter: nil)
        }
    }
}

public enum HTTPStatus {
    /// `nil` for 2xx; otherwise the error the status means.
    public static func error(for response: HTTPResponse, now: Date) -> RemoteError? {
        switch response.status {
        case 200..<300:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 408, 425, 429, 500..<600:
            return .transient(status: response.status, retryAfter: retryAfter(response.header("retry-after"), now: now))
        default:
            return .rejected(status: response.status, reason: String(decoding: response.body.prefix(512), as: UTF8.self))
        }
    }

    /// Parses `Retry-After` as seconds or as an HTTP date.
    public static func retryAfter(_ value: String?, now: Date) -> Duration? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Int(value) {
            return .seconds(max(0, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .milliseconds(max(0, Int64((date.timeIntervalSince(now) * 1000).rounded())))
    }
}
