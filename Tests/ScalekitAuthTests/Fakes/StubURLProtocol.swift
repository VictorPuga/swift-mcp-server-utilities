import Foundation

/// Intercepts every `URLSession.shared` request (registered globally) and replays a canned JWKS
/// response, so `ScalekitTokenValidator`'s JWKS fetch can be tested without real network access.
///
/// Tests using this must run serially (`@Suite(.serialized)`) since the stubbed response is
/// process-global state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    // Guarded by `lock`, not by actor isolation — see `#MutableGlobalVariable` at the call site.
    nonisolated(unsafe) private static var _responseBody: Data = Data()
    nonisolated(unsafe) private static var _statusCode: Int = 200

    static func stub(body: Data, statusCode: Int = 200) {
        lock.withLock {
            _responseBody = body
            _statusCode = statusCode
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (body, statusCode) = Self.lock.withLock { (Self._responseBody, Self._statusCode) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
