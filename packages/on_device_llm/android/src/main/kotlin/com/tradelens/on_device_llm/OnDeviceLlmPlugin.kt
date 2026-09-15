package com.tradelens.on_device_llm

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Stage 1 fallback until the ML Kit Prompt integration is device-verified. */
class OnDeviceLlmPlugin : FlutterPlugin, OnDeviceLlmHostApi {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OnDeviceLlmHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OnDeviceLlmHostApi.setUp(binding.binaryMessenger, null)
    }

    // TODO: Integrate com.google.mlkit:genai-prompt after verifying its version,
    // device eligibility, model readiness, generation, and cancellation on hardware.
    override fun availability(): OnDeviceAvailability = OnDeviceAvailability.UNSUPPORTED_DEVICE

    override suspend fun generate(request: OnDeviceRequest): String =
        throw FlutterError(
            "unsupported",
            "On-device generation is not implemented on Android.",
            null,
        )

    override fun cancel() = Unit

    override fun describeRuntime(): String = "none"
}
