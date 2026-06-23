import Foundation

public enum RelayHostDetector {
    /// Returns the primary LAN IPv4 address suitable for iPhone pairing,
    /// or nil if no suitable address is found.
    ///
    /// Heuristic: looks at IPv4 addresses on `en0` (Wi‑Fi) / `en1` that fall
    /// into private ranges (192.168., 10., 172.16-31.) and are NOT loopback
    /// or link-local.
    public static func primaryLANIPv4() -> String? {
        var addr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addr) == 0, let first = addr else { return nil }
        defer { freeifaddrs(first) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == AF_INET else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)

            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                let parts = ip.split(separator: ".")
                if parts.count == 4, let second = Int(parts[1]), ip.hasPrefix("172.") {
                    guard second >= 16, second <= 31 else { continue }
                }
                return ip
            }
        }
        return nil
    }
}
