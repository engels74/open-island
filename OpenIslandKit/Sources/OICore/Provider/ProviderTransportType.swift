/// The communication transport used by a provider's CLI process.
package enum ProviderTransportType: Sendable, Hashable, BitwiseCopyable {
    case hookSocket
    case jsonRPC
    case httpSSE
}
