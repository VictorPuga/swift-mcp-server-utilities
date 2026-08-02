import Foundation

/// Per-session request stubbing: each call to `makeSession` gets its own isolated handler, keyed
/// by a header `URLSessionConfiguration.httpAdditionalHeaders` stamps onto every request made
/// through that session. Unlike a single process-global stub, this lets tests run concurrently
/// without `@Suite(.serialized)`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handlerHeaderField = "X-Mock-Handler-ID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> (Int, Data)] = [:]

    static func makeSession(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [handlerHeaderField: id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: handlerHeaderField) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: Self.handlerHeaderField),
            let handler = Self.lock.withLock({ Self.handlers[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
