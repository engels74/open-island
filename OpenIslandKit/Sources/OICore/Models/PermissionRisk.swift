/// Risk level for a permission request.
///
/// Maps from Codex's `risk` field in `requestApproval` events.
/// Other providers default to `nil`.
public enum PermissionRisk: Sendable, Hashable, BitwiseCopyable {
    case low
    case medium
    case high
}
