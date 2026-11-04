import Darwin
import Foundation

enum CanvasSocketClient {
    static func call(_ request: CanvasRequest, socketURL: URL) throws -> CanvasReply {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure() }
        defer { Darwin.close(descriptor) }
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketURL.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw failure() }
        var bytes = try JSONEncoder().encode(request)
        bytes.append(10)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw failure() }
                offset += count
            }
        }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !response.contains(10) {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { throw failure() }
            response.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(CanvasReply.self, from: Data(response.prefix { $0 != 10 }))
    }

    private static func failure() -> NSError {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
            NSLocalizedDescriptionKey: "Oncast canvas connection failed (\(String(cString: strerror(code)))). "
                + "Open Excalidraw in Oncast."
        ])
    }
}
