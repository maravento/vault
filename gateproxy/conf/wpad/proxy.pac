function FindProxyForURL(url, host) {
    // Bypass proxy for local resources
    if (
        isPlainHostName(host) ||                             // e.g. http://printer
        shExpMatch(host, "*.local") ||                       // e.g. http://device.local
        isInNet(dnsResolve(host), "192.168.0.0", "255.255.255.0") || // Local subnet
        isInNet(dnsResolve(host), "127.0.0.0", "255.255.255.0")      // Loopback
    ) {
        return "DIRECT";
    }

    // Use main proxy, fallback to intercept proxy if unreachable
    return "PROXY 192.168.0.10:3128; PROXY 192.168.0.10:3129";
}

