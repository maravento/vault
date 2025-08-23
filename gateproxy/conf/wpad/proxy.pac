function FindProxyForURL(url, host) {
    // Localhost
    if (isPlainHostName(host) ||
        shExpMatch(host, "localhost") ||
        isInNet(dnsResolve(host), "127.0.0.0", "255.0.0.0"))
        return "DIRECT";

    // LAN
    if (isInNet(dnsResolve(host), "192.168.0.0", "255.255.255.0"))
        return "DIRECT";

    // Proxy
    if (shExpMatch(host, "192.168.0.10"))
        return "DIRECT";

    // All
    return "PROXY 192.168.0.10:3128; DIRECT";
}


