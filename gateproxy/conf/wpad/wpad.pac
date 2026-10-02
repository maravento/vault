function FindProxyForURL(url, host) {
    if (isPlainHostName(host) || shExpMatch(host, "localhost"))
        return "DIRECT";
    if (shExpMatch(host, "192.168.0.*") || shExpMatch(host, "127.*"))
        return "DIRECT";
    return "PROXY 192.168.0.10:3128; DIRECT";
}
