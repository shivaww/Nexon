package com.termuxforge.app

import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main entry point for the TermuxForge Android application.
 *
 * This activity hosts the Flutter engine and delegates all UI
 * rendering to Flutter. Platform channel communication with
 * Termux and the Python bridge is handled by Flutter plugins
 * and the WebSocket bridge.
 */
class MainActivity : FlutterActivity() {
    private val audioChannelName = "termux_forge/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isHeadsetConnected" -> result.success(isHeadsetConnected())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * True when a wired or Bluetooth headset/headphones are connected.
     * Used by voice mode to decide whether it's safe to keep the mic open
     * while TTS is playing (only safe when audio isn't coming out of the
     * phone's own speaker, since the system speech recognizer's mic
     * session is not one we can attach an echo canceller to).
     */
    private fun isHeadsetConnected(): Boolean {
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_USB_HEADSET -> return true
                else -> {}
            }
        }
        return false
    }
}
