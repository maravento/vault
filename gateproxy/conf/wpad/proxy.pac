function FindProxyForURL(url, host) {
    if (isPlainHostName(host) ||
        isInNet(dnsResolve(host), "192.168.0.0", "255.255.255.0") || // LAN /24
        isInNet(dnsResolve(host), "127.0.0.0", "255.0.0.0"))          // Loopback
        return "DIRECT";

    return "PROXY 192.168.0.10:3128; DIRECT";
}

