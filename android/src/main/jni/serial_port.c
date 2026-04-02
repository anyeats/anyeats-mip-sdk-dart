/*
 * serial_port.c - JNI native code for hardware UART serial port access
 *
 * Opens and configures /dev/ttyS* (and similar) UART ports using termios.
 * Used by SerialPort.kt via JNI on embedded Android devices.
 */

#include <stdio.h>
#include <jni.h>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

static speed_t get_baud_rate(jint baudRate) {
    switch (baudRate) {
        case 300:    return B300;
        case 600:    return B600;
        case 1200:   return B1200;
        case 2400:   return B2400;
        case 4800:   return B4800;
        case 9600:   return B9600;
        case 19200:  return B19200;
        case 38400:  return B38400;
        case 57600:  return B57600;
        case 115200: return B115200;
        case 230400: return B230400;
        case 460800: return B460800;
        case 500000: return B500000;
        case 576000: return B576000;
        case 921600: return B921600;
        default:     return B9600;
    }
}

JNIEXPORT jobject JNICALL
Java_kr_co_anyeats_gs805serial_SerialPort_open(
    JNIEnv *env,
    jobject thiz,
    jstring path,
    jint baudRate,
    jint dataBits,
    jint stopBits,
    jint parity)
{
    const char *device_path = (*env)->GetStringUTFChars(env, path, NULL);
    if (device_path == NULL) {
        jclass exc = (*env)->FindClass(env, "java/io/IOException");
        (*env)->ThrowNew(env, exc, "Failed to get device path string");
        return NULL;
    }

    /* Open the serial port */
    int fd = open(device_path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        char err_msg[256];
        snprintf(err_msg, sizeof(err_msg),
                 "Failed to open %s: %s (errno=%d)",
                 device_path, strerror(errno), errno);
        (*env)->ReleaseStringUTFChars(env, path, device_path);

        jclass exc = (*env)->FindClass(env, "java/io/IOException");
        (*env)->ThrowNew(env, exc, err_msg);
        return NULL;
    }

    (*env)->ReleaseStringUTFChars(env, path, device_path);

    /* Configure the serial port */
    struct termios cfg;
    if (tcgetattr(fd, &cfg) != 0) {
        close(fd);
        jclass exc = (*env)->FindClass(env, "java/io/IOException");
        (*env)->ThrowNew(env, exc, "tcgetattr() failed");
        return NULL;
    }

    /* Raw mode - no echo, no signals, no processing */
    cfmakeraw(&cfg);

    /* Baud rate */
    speed_t speed = get_baud_rate(baudRate);
    cfsetispeed(&cfg, speed);
    cfsetospeed(&cfg, speed);

    /* Data bits */
    cfg.c_cflag &= ~CSIZE;
    switch (dataBits) {
        case 5: cfg.c_cflag |= CS5; break;
        case 6: cfg.c_cflag |= CS6; break;
        case 7: cfg.c_cflag |= CS7; break;
        case 8:
        default: cfg.c_cflag |= CS8; break;
    }

    /* Stop bits */
    if (stopBits == 2) {
        cfg.c_cflag |= CSTOPB;
    } else {
        cfg.c_cflag &= ~CSTOPB;
    }

    /* Parity: 0=none, 1=odd, 2=even */
    cfg.c_cflag &= ~(PARENB | PARODD);
    if (parity == 1) {
        cfg.c_cflag |= PARENB | PARODD; /* odd */
    } else if (parity == 2) {
        cfg.c_cflag |= PARENB;          /* even */
    }

    /* Enable receiver, local mode */
    cfg.c_cflag |= (CLOCAL | CREAD);

    /* No hardware flow control */
    cfg.c_cflag &= ~CRTSCTS;

    /* No software flow control */
    cfg.c_iflag &= ~(IXON | IXOFF | IXANY);

    /* VMIN=0, VTIME=1: return immediately with available data, or after 100ms timeout */
    cfg.c_cc[VMIN] = 0;
    cfg.c_cc[VTIME] = 1;

    if (tcsetattr(fd, TCSANOW, &cfg) != 0) {
        close(fd);
        jclass exc = (*env)->FindClass(env, "java/io/IOException");
        (*env)->ThrowNew(env, exc, "tcsetattr() failed");
        return NULL;
    }

    /* Flush any pending I/O */
    tcflush(fd, TCIOFLUSH);

    /* Clear non-blocking after configuration */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);

    /* Create a FileDescriptor Java object and set its 'fd' field */
    jclass fdClass = (*env)->FindClass(env, "java/io/FileDescriptor");
    jmethodID fdInit = (*env)->GetMethodID(env, fdClass, "<init>", "()V");
    jfieldID fdField = (*env)->GetFieldID(env, fdClass, "descriptor", "I");

    jobject fileDescriptor = (*env)->NewObject(env, fdClass, fdInit);
    (*env)->SetIntField(env, fileDescriptor, fdField, fd);

    return fileDescriptor;
}

JNIEXPORT void JNICALL
Java_kr_co_anyeats_gs805serial_SerialPort_closeNative(
    JNIEnv *env,
    jobject thiz,
    jint fd)
{
    if (fd >= 0) {
        close(fd);
    }
}
