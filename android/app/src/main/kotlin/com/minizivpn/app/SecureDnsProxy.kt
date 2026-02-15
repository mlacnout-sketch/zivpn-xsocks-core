package com.minizivpn.app

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

enum class SecureDnsMode { DOH, DOT }

data class SecureDnsConfig(
    val mode: SecureDnsMode,
    val listenHost: String = "127.0.0.1",
    val listenPort: Int = 5454,
    val dohUrl: String = "https://cloudflare-dns.com/dns-query",
    val dotHost: String = "1.1.1.1",
    val dotPort: Int = 853,
    val timeoutMs: Int = 6000,
    val requireDnssecAd: Boolean = true
)

class SecureDnsProxy(
    private val config: SecureDnsConfig,
    private val protectSocket: (Socket) -> Boolean,
    private val logger: (String) -> Unit
) {
    @Volatile private var running = false
    private var serverSocket: DatagramSocket? = null
    private var worker: Thread? = null

    fun start() {
        if (running) return
        running = true
        worker = Thread {
            try {
                val bindAddress = InetAddress.getByName(config.listenHost)
                val socket = DatagramSocket(config.listenPort, bindAddress)
                serverSocket = socket
                logger("[SecureDNS] Started ${config.mode} proxy on ${config.listenHost}:${config.listenPort}")

                while (running) {
                    val inBuf = ByteArray(4096)
                    val req = DatagramPacket(inBuf, inBuf.size)
                    socket.receive(req)
                    val query = req.data.copyOf(req.length)
                    val answer = handleQuery(query)
                    val resp = DatagramPacket(answer, answer.size, req.address, req.port)
                    socket.send(resp)
                }
            } catch (e: Exception) {
                if (running) logger("[SecureDNS] Proxy crashed: ${e.message}")
            } finally {
                serverSocket?.close()
                serverSocket = null
                running = false
            }
        }
        worker?.isDaemon = true
        worker?.start()
    }

    fun stop() {
        running = false
        try { serverSocket?.close() } catch (_: Exception) {}
        try { worker?.interrupt() } catch (_: Exception) {}
        worker = null
        logger("[SecureDNS] Stopped")
    }

    private fun handleQuery(query: ByteArray): ByteArray {
        return try {
            val response = when (config.mode) {
                SecureDnsMode.DOH -> resolveViaDoh(query)
                SecureDnsMode.DOT -> resolveViaDot(query)
            }
            if (config.requireDnssecAd && !hasAuthenticatedData(response)) {
                logger("[SecureDNS] DNSSEC AD bit missing; returning SERVFAIL")
                buildServFail(query)
            } else {
                response
            }
        } catch (e: Exception) {
            logger("[SecureDNS] Resolve failed: ${e.message}")
            buildServFail(query)
        }
    }

    private fun resolveViaDot(query: ByteArray): ByteArray {
        val socket = Socket()
        if (!protectSocket(socket)) {
            throw IllegalStateException("protect() failed for DoT socket")
        }
        socket.connect(InetSocketAddress(config.dotHost, config.dotPort), config.timeoutMs)
        socket.soTimeout = config.timeoutMs

        val ssl = SSLSocketFactory.getDefault().createSocket(socket, config.dotHost, config.dotPort, true) as SSLSocket
        ssl.useClientMode = true
        ssl.startHandshake()

        val out = DataOutputStream(ssl.outputStream)
        out.writeShort(query.size)
        out.write(query)
        out.flush()

        val input = DataInputStream(ssl.inputStream)
        val length = input.readUnsignedShort()
        val response = ByteArray(length)
        input.readFully(response)
        ssl.close()
        return response
    }

    private fun resolveViaDoh(query: ByteArray): ByteArray {
        val url = URL(config.dohUrl)
        val host = url.host
        val port = if (url.port != -1) url.port else 443
        val path = (if (url.path.isNullOrBlank()) "/dns-query" else url.path) +
            (if (url.query.isNullOrBlank()) "" else "?${url.query}")

        val socket = Socket()
        if (!protectSocket(socket)) {
            throw IllegalStateException("protect() failed for DoH socket")
        }
        socket.connect(InetSocketAddress(host, port), config.timeoutMs)
        socket.soTimeout = config.timeoutMs

        val ssl = SSLSocketFactory.getDefault().createSocket(socket, host, port, true) as SSLSocket
        ssl.useClientMode = true
        ssl.startHandshake()

        val out = DataOutputStream(ssl.outputStream)
        out.writeBytes("POST $path HTTP/1.1\r\n")
        out.writeBytes("Host: $host\r\n")
        out.writeBytes("Accept: application/dns-message\r\n")
        out.writeBytes("Content-Type: application/dns-message\r\n")
        out.writeBytes("Content-Length: ${query.size}\r\n")
        out.writeBytes("Connection: close\r\n\r\n")
        out.write(query)
        out.flush()

        val input = ssl.inputStream
        val raw = ByteArrayOutputStream()
        val buf = ByteArray(4096)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            raw.write(buf, 0, n)
        }
        ssl.close()

        val bytes = raw.toByteArray()
        val separator = "\r\n\r\n".toByteArray()
        val headerEnd = indexOf(bytes, separator)
        if (headerEnd <= 0) throw IllegalStateException("Invalid DoH response")

        val lineEnd = indexOf(bytes, "\r\n".toByteArray())
        val statusLine = if (lineEnd > 0) String(bytes, 0, lineEnd) else "HTTP/1.1 500"
        if (!statusLine.contains(" 200 ")) throw IllegalStateException("DoH HTTP status not OK: $statusLine")

        return bytes.copyOfRange(headerEnd + separator.size, bytes.size)
    }

    private fun hasAuthenticatedData(response: ByteArray): Boolean {
        if (response.size < 4) return false
        val flags = ((response[2].toInt() and 0xFF) shl 8) or (response[3].toInt() and 0xFF)
        return (flags and 0x0020) != 0
    }

    private fun buildServFail(query: ByteArray): ByteArray {
        val id0 = if (query.isNotEmpty()) query[0] else 0
        val id1 = if (query.size > 1) query[1] else 0
        val rd = if (query.size > 2 && (query[2].toInt() and 0x01) == 0x01) 0x01 else 0x00
        val flags1 = (0x80 or rd).toByte() // QR + RD(if requested)
        val flags2 = 0x82.toByte() // RA + SERVFAIL
        return byteArrayOf(
            id0, id1,
            flags1, flags2,
            0x00, 0x01,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00
        ) + if (query.size > 12) query.copyOfRange(12, query.size) else byteArrayOf()
    }

    private fun indexOf(data: ByteArray, needle: ByteArray): Int {
        if (needle.isEmpty() || data.size < needle.size) return -1
        outer@ for (i in 0..data.size - needle.size) {
            for (j in needle.indices) if (data[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }
}
