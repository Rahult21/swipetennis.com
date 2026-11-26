import Foundation

enum CupAPI {
  static var url: URL? {
    #if targetEnvironment(simulator)
    // Explicit localhost fixtures let UI tests use real API sessions without
    // Apple sign-in. This branch is absent from every physical-device build.
    if let local = localTestURL { return local }
    #endif
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CoachAPIURL") as? String,
      let url = URL(string: value), url.scheme == "https" else { return nil }
    return url
  }
  static var localTestURL: URL? {
    #if targetEnvironment(simulator)
    guard let value = ProcessInfo.processInfo.environment["SWIPETENNIS_LOCAL_TEST_URL"],
      let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1", url.port == 8788,
      ["/api", "/api/"].contains(url.path), url.user == nil, url.password == nil else { return nil }
    return url
    #else
    return nil
    #endif
  }
  static var localTestIdentity: CoachIdentity? {
    #if targetEnvironment(simulator)
    guard localTestURL != nil,
      let token = ProcessInfo.processInfo.environment["SWIPETENNIS_LOCAL_TEST_TOKEN"], token.count == 64,
      let id = ProcessInfo.processInfo.environment["SWIPETENNIS_LOCAL_TEST_USER"] else { return nil }
    return CoachIdentity(token: token, userID: id, emailMask: "Local player")
    #else
    return nil
    #endif
  }
}
