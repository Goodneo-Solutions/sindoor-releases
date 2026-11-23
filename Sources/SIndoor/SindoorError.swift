import Foundation

/// An error of the engine, the Open Platform or the SDK: a stable `code` (`invalid_site`, `bad_download`,
/// `unknown_point`, `unknown_level`, `site_not_found`, `http_404`, `permission_missing` …), a message and the refs it
/// concerns. The same codes as the Web SDK's `SindoorError`.
public struct SindoorError: Error, Equatable, CustomStringConvertible, LocalizedError {
    public let code: String
    public let message: String
    public let refs: [String]

    public init(_ code: String, _ message: String = "", refs: [String] = []) {
        self.code = code
        self.message = message.isEmpty ? code : message
        self.refs = refs
    }

    public var description: String { "SindoorError(\(code)): \(message)" }
    public var errorDescription: String? { message }

    /// `{"error": {code, message, refs}}` → the error; anything else → nil.
    static func from(answer v: Any?) -> SindoorError? {
        guard let o = v as? [String: Any], let e = o["error"] as? [String: Any] else { return nil }
        return SindoorError((e["code"] as? String) ?? "error", (e["message"] as? String) ?? "", refs: (e["refs"] as? [Any])?.map { "\($0)" } ?? [])
    }
}
