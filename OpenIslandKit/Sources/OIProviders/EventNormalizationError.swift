package enum EventNormalizationError: Error, Sendable {
    case unknownEventType(String)
    case malformedPayload(field: String)
    case missingRequiredField(String)
}
