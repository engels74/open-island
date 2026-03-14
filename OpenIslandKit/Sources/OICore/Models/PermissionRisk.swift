/// Risk level for a permission request.
///
/// Maps from Codex's `risk` field in `requestApproval` events.
/// Other providers default to `nil`.
package enum PermissionRisk: Sendable, Hashable, BitwiseCopyable {
    case low
    case medium
    case high
}
