import GoogleCloudAuth

struct FakeTokenProvider: GoogleAccessTokenProvider {
    let token: String
    func accessToken() async throws -> String { token }
}
