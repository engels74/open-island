/// The communication transport used by a provider's CLI process.
public enum ProviderTransportType: Sendable, Hashable, BitwiseCopyable {
    case hookSocket
    case jsonRPC
    case httpSSE
}
