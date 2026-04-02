package kr.co.anyeats.gs805serial

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform channel handler for UART serial communication.
 *
 * Handles MethodChannel calls for connect/disconnect/write/listDevices,
 * and provides an EventChannel for streaming incoming serial data.
 */
class UartMethodChannelHandler(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "gs805serial/uart"
        const val EVENT_CHANNEL = "gs805serial/uart_input"

        /** Common UART device path prefixes on Android */
        private val UART_PREFIXES = listOf(
            "/dev/ttyS",
            "/dev/ttyHS",
            "/dev/ttyMT",
            "/dev/ttyAMA",
            "/dev/ttySAC",
            "/dev/ttyUSB",
            "/dev/ttyACM",
        )

        private const val READ_BUFFER_SIZE = 1024
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var serialPort: SerialPort? = null
    private var readExecutor: ExecutorService? = null
    private var eventSink: EventChannel.EventSink? = null
    @Volatile
    private var isReading = false

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDevices" -> listDevices(result)
            "connect" -> {
                val path = call.argument<String>("path")
                val baudRate = call.argument<Int>("baudRate") ?: 9600
                val dataBits = call.argument<Int>("dataBits") ?: 8
                val stopBits = call.argument<Int>("stopBits") ?: 1
                val parity = call.argument<Int>("parity") ?: 0

                if (path == null) {
                    result.error("INVALID_ARGUMENT", "Device path is required", null)
                    return
                }
                connect(path, baudRate, dataBits, stopBits, parity, result)
            }
            "disconnect" -> disconnect(result)
            "write" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("INVALID_ARGUMENT", "Data is required", null)
                    return
                }
                write(data, result)
            }
            "isConnected" -> {
                result.success(serialPort?.isOpen == true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Scan /dev for available UART devices.
     */
    private fun listDevices(result: MethodChannel.Result) {
        try {
            val devices = mutableListOf<Map<String, Any?>>()

            // Scan by known patterns to find all ports including busy ones
            val patterns = listOf(
                Pair("/dev/ttyS", 0..31),
                Pair("/dev/ttyHS", 0..15),
                Pair("/dev/ttyMT", 0..15),
                Pair("/dev/ttyAMA", 0..15),
                Pair("/dev/ttySAC", 0..15),
                Pair("/dev/ttyUSB", 0..15),
                Pair("/dev/ttyACM", 0..15),
            )

            for ((prefix, range) in patterns) {
                for (i in range) {
                    val file = File("$prefix$i")
                    if (file.exists()) {
                        devices.add(
                            mapOf(
                                "id" to file.absolutePath,
                                "name" to file.name,
                                "path" to file.absolutePath,
                                "readable" to file.canRead(),
                                "writable" to file.canWrite(),
                            )
                        )
                    }
                }
            }

            // Sort by path for consistent ordering
            devices.sortBy { it["path"] as String }
            result.success(devices)
        } catch (e: Exception) {
            result.error("LIST_ERROR", "Failed to list UART devices: ${e.message}", null)
        }
    }

    /**
     * Open and connect to a UART serial port.
     */
    private fun connect(
        path: String,
        baudRate: Int,
        dataBits: Int,
        stopBits: Int,
        parity: Int,
        result: MethodChannel.Result
    ) {
        if (serialPort?.isOpen == true) {
            result.error("ALREADY_CONNECTED", "Already connected. Disconnect first.", null)
            return
        }

        try {
            val port = SerialPort(path)
            port.open(baudRate, dataBits, stopBits, parity)
            serialPort = port

            // Start reading in a background thread
            startReading()

            result.success(true)
        } catch (e: Exception) {
            serialPort = null
            result.error("CONNECT_ERROR", "Failed to connect to $path: ${e.message}", null)
        }
    }

    /**
     * Disconnect from the current serial port.
     */
    private fun disconnect(result: MethodChannel.Result) {
        try {
            stopReading()
            serialPort?.close()
            serialPort = null
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", "Failed to disconnect: ${e.message}", null)
        }
    }

    /**
     * Write data to the serial port.
     */
    private fun write(data: ByteArray, result: MethodChannel.Result) {
        val port = serialPort
        if (port == null || !port.isOpen) {
            result.error("NOT_CONNECTED", "Not connected to any device", null)
            return
        }

        try {
            port.outputStream?.write(data)
            port.outputStream?.flush()
            result.success(data.size)
        } catch (e: Exception) {
            result.error("WRITE_ERROR", "Failed to write data: ${e.message}", null)
        }
    }

    /**
     * Start a background thread to continuously read from the serial port
     * and send data to the EventChannel.
     */
    private fun startReading() {
        stopReading()
        isReading = true
        readExecutor = Executors.newSingleThreadExecutor()
        readExecutor?.execute {
            val buffer = ByteArray(READ_BUFFER_SIZE)
            while (isReading) {
                try {
                    val inputStream = serialPort?.inputStream ?: break
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead > 0) {
                        val data = buffer.copyOf(bytesRead)
                        mainHandler.post {
                            eventSink?.success(data)
                        }
                    } else if (bytesRead < 0) {
                        // Stream closed
                        break
                    }
                } catch (e: Exception) {
                    if (isReading) {
                        mainHandler.post {
                            eventSink?.error("READ_ERROR", "Read error: ${e.message}", null)
                        }
                    }
                    break
                }
            }
        }
    }

    /**
     * Stop the background reading thread.
     */
    private fun stopReading() {
        isReading = false
        readExecutor?.shutdownNow()
        readExecutor = null
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Clean up all resources. Called when the plugin is detached.
     */
    fun dispose() {
        stopReading()
        serialPort?.close()
        serialPort = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
