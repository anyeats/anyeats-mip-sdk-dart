package kr.co.anyeats.gs805serial

import java.io.File
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

/**
 * Native serial port wrapper for hardware UART access.
 *
 * Opens /dev/ttyS* (and similar) UART ports via JNI using termios.
 * Provides FileInputStream/FileOutputStream for reading/writing data.
 */
class SerialPort(val devicePath: String) {

    private var fileDescriptor: FileDescriptor? = null

    /** Input stream for reading data from the serial port */
    var inputStream: FileInputStream? = null
        private set

    /** Output stream for writing data to the serial port */
    var outputStream: FileOutputStream? = null
        private set

    /** Whether the port is currently open */
    val isOpen: Boolean
        get() = fileDescriptor != null

    /**
     * Open the serial port with the given configuration.
     *
     * @param baudRate Baud rate (e.g. 9600, 115200)
     * @param dataBits Number of data bits (5-8)
     * @param stopBits Number of stop bits (1 or 2)
     * @param parity Parity mode (0=none, 1=odd, 2=even)
     * @throws IOException if the port cannot be opened
     */
    fun open(baudRate: Int, dataBits: Int, stopBits: Int, parity: Int) {
        val device = File(devicePath)
        if (!device.exists()) {
            throw IOException("Serial device not found: $devicePath")
        }

        // Check read/write permissions
        if (!device.canRead() || !device.canWrite()) {
            // Try to set permissions via su (common on embedded Android)
            try {
                val process = Runtime.getRuntime().exec(
                    arrayOf("su", "-c", "chmod 666 $devicePath")
                )
                process.waitFor()
            } catch (e: Exception) {
                // Ignore - permission may already be sufficient via SELinux policy
            }

            if (!device.canRead() || !device.canWrite()) {
                throw IOException(
                    "No read/write permission for $devicePath. " +
                    "Ensure the app has appropriate permissions or the device node is accessible."
                )
            }
        }

        fileDescriptor = open(devicePath, baudRate, dataBits, stopBits, parity)
        inputStream = FileInputStream(fileDescriptor)
        outputStream = FileOutputStream(fileDescriptor)
    }

    /**
     * Close the serial port and release resources.
     */
    fun close() {
        try {
            inputStream?.close()
        } catch (e: Exception) {
            // Ignore close errors
        }
        try {
            outputStream?.close()
        } catch (e: Exception) {
            // Ignore close errors
        }

        fileDescriptor?.let { fd ->
            try {
                val fdField = FileDescriptor::class.java.getDeclaredField("descriptor")
                fdField.isAccessible = true
                val fdInt = fdField.getInt(fd)
                closeNative(fdInt)
            } catch (e: Exception) {
                // Ignore
            }
        }

        inputStream = null
        outputStream = null
        fileDescriptor = null
    }

    // JNI native methods
    private external fun open(
        path: String,
        baudRate: Int,
        dataBits: Int,
        stopBits: Int,
        parity: Int
    ): FileDescriptor

    private external fun closeNative(fd: Int)

    companion object {
        init {
            System.loadLibrary("serial_port")
        }
    }
}
