import Flutter
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public final class OnDeviceLlmPlugin: NSObject, FlutterPlugin, OnDeviceLlmHostApi {
    private var generationTask: Task<String, Error>?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = OnDeviceLlmPlugin()
        OnDeviceLlmHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    func availability(languageCode: String) throws -> OnDeviceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return modelAvailability(languageCode: languageCode)
        }
        #endif
        return .unsupportedOs
    }

    func describeRuntime() throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return "Apple Foundation Models"
        }
        #endif
        return "none"
    }

    func cancel() throws {
        generationTask?.cancel()
    }

    func generate(request: OnDeviceRequest) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                return try await generateWithFoundationModels(request: request)
            } catch {
                throw Self.generationFailed(error)
            }
        }
        #endif
        throw Self.generationFailed()
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func modelAvailability(languageCode: String) -> OnDeviceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            guard SystemLanguageModel.default.supportsLocale(
                Locale(identifier: languageCode)
            ) else {
                return .unsupportedLanguage
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            return .disabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unsupportedDevice
        @unknown default:
            return .unsupportedDevice
        }
    }

    @available(iOS 26, *)
    private func generateWithFoundationModels(
        request: OnDeviceRequest
    ) async throws -> String {
        guard request.maxOutputChars > 0, generationTask == nil else {
            throw Self.generationFailed()
        }

        let task = Task<String, Error> {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: request.system)
            let response = try await session.respond(to: request.prompt)
            try Task.checkCancellation()
            // Character.prefix preserves complete grapheme clusters.
            return String(response.content.prefix(Int(request.maxOutputChars)))
        }
        generationTask = task
        defer { generationTask = nil }
        return try await task.value
    }
    #endif

    private static func generationFailed(_ error: Error? = nil) -> PigeonError {
        let flutterError = FlutterError(
            code: "generation_failed",
            message: error?.localizedDescription ?? "On-device generation failed.",
            details: nil
        )
        return PigeonError(
            code: flutterError.code,
            message: flutterError.message,
            details: flutterError.details
        )
    }
}
