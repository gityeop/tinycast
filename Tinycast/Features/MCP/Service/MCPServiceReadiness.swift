import Darwin
import Foundation

enum MCPServiceReadiness {
    nonisolated static func isListening(port: Int) async -> Bool {
        await Task.detached {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 { return true }
            guard errno == EINPROGRESS else { return false }
            var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            guard poll(&event, 1, 100) > 0 else { return false }
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            return getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0
        }.value
    }
}
