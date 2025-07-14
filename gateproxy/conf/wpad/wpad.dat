function FindProxyForURL(url, host) {
// If the requested website is hosted within the internal network, send direct.
    if (isPlainHostName(host) ||
        shExpMatch(host, "*.local") ||
        isInNet(dnsResolve(host), "192.168.0.0", "255.255.0.0") ||
        isInNet(dnsResolve(host), "127.0.0.0", "255.255.255.0"))
        return "DIRECT";

// If the IP address of the local machine is within a defined
// subnet, send to a specific proxy.
    if (isInNet(myIpAddress(), "192.168.0.0", "255.255.255.0"))
        return "PROXY 192.168.0.10:3128";

// DEFAULT RULE: All other traffic, use below proxies, in fail-over order. Example:
//    return "PROXY 192.168.0.10:3128; PROXY 192.168.0.10:8080"; }
    return "PROXY 192.168.0.10:3128"; }
