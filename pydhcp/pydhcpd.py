#!/usr/bin/env python3
# pydhcpd.py — Python DHCP Daemon
# maravento.com
#
# Drop-in replacement for isc-dhcp-server.
# Reads /etc/pydhcp/pydhcpd.conf and /etc/pydhcp/pydhcpd.defaults,
# writes /etc/pydhcp/pydhcpd.leases and /etc/pydhcp/pydhcpd.pid.
#
# Supported dhcpd.conf directives:
#   authoritative, server-identifier, deny duplicates,
#   one-lease-per-client, deny declines, deny client-updates,
#   ping-check, ddns-update-style, log-facility,
#   host { hardware ethernet; fixed-address; }
#   class "blockdhcp" { match pick-first-value ... }
#   subclass "blockdhcp" 1:<mac>;
#   subnet { option routers, subnet-mask, broadcast-address,
#             domain-name-servers, wpad;
#             min/default/max-lease-time;
#             pool { deny members of "blockdhcp"; range; } }
#
# Requirements: Python 3.8+, no external dependencies.
# Run as root. User/group pydhcpd must exist.

import os
import sys
import socket
import struct
import time
import re
import signal
import logging
import threading
import subprocess
import ipaddress
import collections
from datetime import datetime, timezone
import pwd
import grp

# =============================================================================
# PATHS
# =============================================================================

BASE_DIR        = "/etc/pydhcp"
DEFAULTS_FILE   = os.path.join(BASE_DIR, "pydhcpd.defaults")
CONF_FILE       = os.path.join(BASE_DIR, "pydhcpd.conf")
LEASES_FILE     = os.path.join(BASE_DIR, "pydhcpd.leases")
PID_FILE        = os.path.join(BASE_DIR, "pydhcpd.pid")
LOG_FILE        = "/var/log/pydhcpd.log"

# =============================================================================
# LOGGING
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("pydhcpd")

# =============================================================================
# DHCP CONSTANTS
# =============================================================================

DHCP_SERVER_PORT = 67
DHCP_CLIENT_PORT = 68
BROADCAST_ADDR   = "255.255.255.255"  # overridden at runtime with subnet broadcast
DHCP_MAGIC       = b"\x63\x82\x53\x63"
ETH_P_IP         = 0x0800

MSG_DISCOVER = 1
MSG_OFFER    = 2
MSG_REQUEST  = 3
MSG_DECLINE  = 4
MSG_ACK      = 5
MSG_NAK      = 6
MSG_RELEASE  = 7
MSG_INFORM   = 8

OPT_SUBNET_MASK        = 1
OPT_ROUTERS            = 3
OPT_DNS                = 6
OPT_BROADCAST          = 28
OPT_REQUESTED_IP       = 50
OPT_LEASE_TIME         = 51
OPT_MSG_TYPE           = 53
OPT_SERVER_ID          = 54
OPT_PARAM_REQUEST_LIST = 55
OPT_MAX_MSG_SIZE       = 57
OPT_CLIENT_ID          = 61
OPT_WPAD               = 252
OPT_END                = 255

# =============================================================================
# DEFAULTS PARSER
# =============================================================================

def parse_defaults(path):
    """Parse /etc/pydhcp/pydhcpd.defaults (shell variable format)."""
    defaults = {
        "conf":      CONF_FILE,
        "pid":       PID_FILE,
        "interface": "",
        "user":      "pydhcpd",
        "group":     "pydhcpd",
    }
    if not os.path.isfile(path):
        log.warning("Defaults file not found: %s", path)
        return defaults
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            val = val.strip().strip('"').strip("'")
            key = key.strip()
            if key == "DHCPDv4_CONF":
                defaults["conf"] = val
            elif key == "DHCPDv4_PID":
                defaults["pid"] = val
            elif key == "INTERFACESv4":
                defaults["interface"] = val.split()[0] if val.split() else ""
            elif key == "DAEMON_USER":
                defaults["user"] = val
            elif key == "DAEMON_GROUP":
                defaults["group"] = val
    return defaults

# =============================================================================
# CONF PARSER
# =============================================================================

class DHCPConfig:
    """
    Parses a dhcpd.conf-compatible file and exposes the configuration
    as structured Python objects.
    """

    def __init__(self):
        self.server_id        = ""
        self.authoritative    = False
        self.deny_duplicates  = False
        self.one_per_client   = False
        self.deny_declines    = False
        self.deny_client_upd  = False
        self.ping_check       = False

        self.subnet           = ""
        self.netmask          = ""
        self.routers          = ""
        self.broadcast        = ""
        self.dns_servers      = []
        self.wpad_url         = ""
        self.min_lease        = 120
        self.default_lease    = 120
        self.max_lease        = 120

        self.pool_range_start = ""
        self.pool_range_end   = ""
        self.pool_min_lease   = 120
        self.pool_def_lease   = 120
        self.pool_max_lease   = 120

        self.static_hosts     = {}   # mac -> ip
        self.blocked_macs     = set()

    def load(self, path):
        if not os.path.isfile(path):
            log.error("Config file not found: %s", path)
            sys.exit(1)

        with open(path) as f:
            raw = f.read()

        # Strip comments
        raw = re.sub(r'#[^\n]*', '', raw)

        self._parse(raw)
        log.info("Config loaded: %d static hosts, %d blocked MACs",
                 len(self.static_hosts), len(self.blocked_macs))

    def _parse(self, raw):
        # Global directives
        self.authoritative   = bool(re.search(r'\bauthoritative\s*;', raw))
        self.deny_duplicates = bool(re.search(r'\bdeny\s+duplicates\s*;', raw))
        self.one_per_client  = bool(re.search(r'\bone-lease-per-client\s+true\s*;', raw))
        self.deny_declines   = bool(re.search(r'\bdeny\s+declines\s*;', raw))
        self.deny_client_upd = bool(re.search(r'\bdeny\s+client-updates\s*;', raw))
        self.ping_check      = bool(re.search(r'\bping-check\s+true\s*;', raw))

        m = re.search(r'\bserver-identifier\s+([\d.]+)\s*;', raw)
        if m:
            self.server_id = m.group(1)

        # Static host blocks: host NAME { hardware ethernet MAC; fixed-address IP; }
        for m in re.finditer(
            r'\bhost\s+\S+\s*\{(.*?)\}',
            raw, re.IGNORECASE | re.DOTALL
        ):
            block = m.group(1)
            mac_m = re.search(r'hardware\s+ethernet\s+([\da-f:]+)\s*;', block, re.IGNORECASE)
            ip_m  = re.search(r'fixed-address\s+([\d.]+)\s*;', block, re.IGNORECASE)
            if mac_m and ip_m:
                self.static_hosts[mac_m.group(1).lower()] = ip_m.group(1)

        # Blocked MACs: subclass "blockdhcp" 1:MAC;
        for m in re.finditer(
            r'\bsubclass\s+"blockdhcp"\s+1:([\da-f:]+)\s*;',
            raw, re.IGNORECASE
        ):
            self.blocked_macs.add(m.group(1).lower())

        # Subnet block
        m = re.search(
            r'\bsubnet\s+([\d.]+)\s+netmask\s+([\d.]+)\s*\{(.*?)\}(?!\s*\})',
            raw, re.DOTALL
        )
        if m:
            self.subnet  = m.group(1)
            self.netmask = m.group(2)
            subnet_body  = m.group(3)
            self._parse_subnet(subnet_body)

    def _parse_subnet(self, body):
        def lease_seconds(s):
            return int(s)

        m = re.search(r'option\s+routers\s+([\d.]+)\s*;', body)
        if m:
            self.routers = m.group(1)

        m = re.search(r'option\s+broadcast-address\s+([\d.]+)\s*;', body)
        if m:
            self.broadcast = m.group(1)

        m = re.search(r'option\s+domain-name-servers\s+([^;]+);', body)
        if m:
            entries = [s.strip() for s in m.group(1).split(",") if s.strip()]
            resolved = []
            for entry in entries:
                if re.match(r'^\d+\.\d+\.\d+\.\d+$', entry):
                    resolved.append(entry)
                else:
                    try:
                        resolved.append(socket.gethostbyname(entry))
                    except socket.gaierror:
                        log.warning("Cannot resolve DNS server hostname: %s (skipped)", entry)
            self.dns_servers = resolved

        m = re.search(r'option\s+wpad\s+"([^"]+)"\s*;', body)
        if m:
            self.wpad_url = m.group(1)

        m = re.search(r'min-lease-time\s+(\d+)\s*;', body)
        if m:
            self.min_lease = lease_seconds(m.group(1))

        m = re.search(r'default-lease-time\s+(\d+)\s*;', body)
        if m:
            self.default_lease = lease_seconds(m.group(1))

        m = re.search(r'max-lease-time\s+(\d+)\s*;', body)
        if m:
            self.max_lease = lease_seconds(m.group(1))

        # Pool block
        pool_m = re.search(r'\bpool\s*\{(.*?)\}', body, re.DOTALL)
        if pool_m:
            pool = pool_m.group(1)

            m = re.search(r'range\s+([\d.]+)\s+([\d.]+)\s*;', pool)
            if m:
                self.pool_range_start = m.group(1)
                self.pool_range_end   = m.group(2)

            m = re.search(r'min-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_min_lease = lease_seconds(m.group(1))

            m = re.search(r'default-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_def_lease = lease_seconds(m.group(1))

            m = re.search(r'max-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_max_lease = lease_seconds(m.group(1))

# =============================================================================
# LEASE MANAGER
# =============================================================================

class Lease:
    def __init__(self, ip, mac, hostname, start, end, binding="active"):
        self.ip       = ip
        self.mac      = mac
        self.hostname = re.sub(r'[\x00-\x1f\x7f"\\]', '', str(hostname))[:64]
        self.start    = start
        self.end      = end
        self.binding  = binding

    def is_expired(self):
        return time.time() > self.end

    def to_conf(self):
        """Serialize to dhcpd.leases format."""
        fmt = "%Y/%m/%d %H:%M:%S"
        start_str = datetime.fromtimestamp(self.start, tz=timezone.utc).strftime(fmt)
        end_str   = datetime.fromtimestamp(self.end,   tz=timezone.utc).strftime(fmt)
        lines = [
            f"lease {self.ip} {{",
            f"  starts 0 {start_str};",
            f"  ends 0 {end_str};",
            f"  binding state {self.binding};",
            f"  hardware ethernet {self.mac};",
        ]
        if self.hostname:
            lines.append(f"  client-hostname \"{self.hostname}\";")
        lines.append("}")
        return "\n".join(lines) + "\n"


class LeaseManager:
    def __init__(self, path, config, daemon_user="pydhcpd", daemon_group="pydhcpd"):
        self.path   = path
        self.config = config
        self.lock   = threading.Lock()
        self.leases = {}   # ip -> Lease
        self._uid   = None
        self._gid   = None
        try:
            self._uid = pwd.getpwnam(daemon_user).pw_uid
            self._gid = grp.getgrnam(daemon_group).gr_gid
        except KeyError:
            log.warning("User/group %s:%s not found — leases file chown skipped",
                        daemon_user, daemon_group)
        self._load()
        self._build_pool()

    def _load(self):
        if not os.path.isfile(self.path):
            return
        with open(self.path) as f:
            raw = f.read()
        for m in re.finditer(
            r'lease\s+([\d.]+)\s*\{(.*?)\}',
            raw, re.DOTALL
        ):
            ip   = m.group(1)
            body = m.group(2)

            mac_m  = re.search(r'hardware\s+ethernet\s+([\da-f:]+)\s*;', body, re.IGNORECASE)
            host_m = re.search(r'client-hostname\s+"([^"]+)"\s*;', body)
            bind_m = re.search(r'binding\s+state\s+(\w+)\s*;', body)
            end_m  = re.search(r'ends\s+\d+\s+([\d/]+ [\d:]+)\s*;', body)

            if not mac_m or not end_m:
                continue

            mac      = mac_m.group(1).lower()
            hostname = host_m.group(1) if host_m else ""
            binding  = bind_m.group(1) if bind_m else "active"
            try:
                end = datetime.strptime(end_m.group(1), "%Y/%m/%d %H:%M:%S").replace(
                    tzinfo=timezone.utc).timestamp()
            except ValueError:
                continue

            lease = Lease(ip, mac, hostname, time.time(), end, binding)
            self.leases[ip] = lease

        log.info("Leases loaded: %d entries", len(self.leases))

    def _build_pool(self):
        """Build the list of available IPs from the pool range."""
        self.pool = []
        if not self.config.pool_range_start or not self.config.pool_range_end:
            return
        try:
            start = ipaddress.IPv4Address(self.config.pool_range_start)
            end   = ipaddress.IPv4Address(self.config.pool_range_end)
            ip    = start
            while ip <= end:
                self.pool.append(str(ip))
                ip += 1
        except ValueError as e:
            log.error("Invalid pool range: %s", e)

    def save(self):
        with self.lock:
            snapshot = dict(self.leases)
        self._save_snapshot(snapshot)

    def get_by_mac(self, mac):
        mac = mac.lower()
        for lease in self.leases.values():
            if lease.mac == mac and not lease.is_expired():
                return lease
        return None

    def get_static(self, mac):
        mac = mac.lower()
        return self.config.static_hosts.get(mac)

    def is_blocked(self, mac):
        return mac.lower() in self.config.blocked_macs

    def allocate(self, mac, hostname, requested_ip=None):
        """
        Returns (ip, lease_time) for the given MAC.
        Static hosts get their fixed IP and full lease time.
        Blocked MACs get a pool IP with short lease time.
        Unknown MACs that are not blocked go to blockdhcp pool.
        """
        mac = mac.lower()

        # Static reservation — no lease entry written for fixed-address clients
        static_ip = self.get_static(mac)
        if static_ip:
            return static_ip, self.config.default_lease

        # Blocked MAC → assign pool IP with short lease
        if self.is_blocked(mac):
            ip = self._get_pool_ip(mac)
            if ip:
                self._create_lease(ip, mac, hostname, self.config.pool_def_lease)
                return ip, self.config.pool_def_lease
            return None, None

        # Unknown MAC → goes to block pool (will be registered in blockdhcp by pyleases.sh)
        ip = self._get_pool_ip(mac)
        if ip:
            self._create_lease(ip, mac, hostname, self.config.pool_def_lease)
            return ip, self.config.pool_def_lease

        return None, None

    def _get_pool_ip(self, mac):
        existing = self.get_by_mac(mac)
        if existing and existing.ip in self.pool:
            return existing.ip

        static_ips = set(self.config.static_hosts.values())
        used = set(self.leases.keys()) | static_ips
        for ip in self.pool:
            if ip not in used:
                return ip
        return None

    def _create_lease(self, ip, mac, hostname, duration):
        now = time.time()
        lease = Lease(ip, mac, hostname, now, now + duration)
        with self.lock:
            self.leases[ip] = lease
            snapshot = dict(self.leases)
        self._save_snapshot(snapshot)

    def _save_snapshot(self, snapshot):
        with open(self.path, "w") as f:
            for lease in snapshot.values():
                f.write(lease.to_conf())
                f.write("\n")
        if self._uid is not None and self._gid is not None:
            try:
                os.chown(self.path, self._uid, self._gid)
            except PermissionError:
                pass
        os.chmod(self.path, 0o640)

    def release(self, mac):
        mac = mac.lower()
        snapshot = None
        with self.lock:
            to_del = [ip for ip, l in self.leases.items() if l.mac == mac]
            for ip in to_del:
                del self.leases[ip]
            if to_del:
                snapshot = dict(self.leases)
        if snapshot is not None:
            self._save_snapshot(snapshot)

    def cleanup_expired(self):
        snapshot = None
        with self.lock:
            expired = [ip for ip, l in self.leases.items() if l.is_expired()]
            for ip in expired:
                log.info("Lease expired: %s", ip)
                del self.leases[ip]
            if expired:
                snapshot = dict(self.leases)
        if snapshot is not None:
            self._save_snapshot(snapshot)

# =============================================================================
# DHCP PACKET
# =============================================================================

def mac_bytes_to_str(b):
    return ":".join(f"{x:02x}" for x in b[:6])

def ip_to_bytes(ip_str):
    return socket.inet_aton(ip_str)

def bytes_to_ip(b):
    return socket.inet_ntoa(b)

def parse_packet(data):
    """Parse a raw DHCP packet into a dict."""
    if len(data) < 240:
        return None

    pkt = {}
    pkt["op"]    = data[0]
    pkt["htype"] = data[1]
    if pkt["htype"] != 1:
        return None
    pkt["hlen"]  = data[2]
    pkt["xid"]   = data[4:8]
    pkt["flags"] = struct.unpack("!H", data[10:12])[0]
    pkt["ciaddr"] = bytes_to_ip(data[12:16])
    pkt["yiaddr"] = bytes_to_ip(data[16:20])
    pkt["siaddr"] = bytes_to_ip(data[20:24])
    pkt["giaddr"] = bytes_to_ip(data[24:28])
    pkt["chaddr"] = mac_bytes_to_str(data[28:34])

    if data[236:240] != DHCP_MAGIC:
        return None

    pkt["options"] = {}
    i = 240
    while i < len(data):
        opt = data[i]
        if opt == OPT_END:
            break
        if opt == 0:
            i += 1
            continue
        if i + 1 >= len(data):
            break
        length = data[i + 1]
        value  = data[i + 2: i + 2 + length]
        pkt["options"][opt] = value
        i += 2 + length

    pkt["msg_type"] = pkt["options"].get(OPT_MSG_TYPE, b"\x00")[0]
    raw_hostname = pkt["options"].get(12, b"").decode("ascii", errors="replace").strip("\x00").strip()
    pkt["hostname"] = re.sub(r'[\x00-\x1f\x7f"\\]', '', raw_hostname).strip()
    pkt["requested_ip"] = bytes_to_ip(pkt["options"].get(OPT_REQUESTED_IP, b"\x00\x00\x00\x00"))

    return pkt


def build_packet(msg_type, xid, mac_str, offered_ip, server_ip, config, lease_time):
    """Build a DHCP OFFER or ACK packet."""
    try:
        mac_bytes = bytes(int(x, 16) for x in mac_str.split(":"))
        if len(mac_bytes) != 6:
            raise ValueError("Invalid MAC length")
    except ValueError:
        log.error("Invalid MAC address format: %s", mac_str)
        return b""  

    pkt = bytearray(236)
    pkt[0]  = 2                         # op: BOOTREPLY
    pkt[1]  = 1                         # htype: Ethernet
    pkt[2]  = 6                         # hlen
    pkt[3]  = 0                         # hops
    pkt[4:8] = xid                      # transaction id
    pkt[10:12] = struct.pack("!H", 0x8000)  # flags: broadcast
    pkt[16:20] = ip_to_bytes(offered_ip)    # yiaddr
    pkt[20:24] = ip_to_bytes(server_ip)     # siaddr
    pkt[28:34] = mac_bytes                  # chaddr

    options = bytearray()
    options += DHCP_MAGIC

    def add_opt(code, value):
        nonlocal options
        options += bytes([code, len(value)]) + value

    add_opt(OPT_MSG_TYPE,  bytes([msg_type]))
    add_opt(OPT_SERVER_ID, ip_to_bytes(server_ip))
    add_opt(OPT_LEASE_TIME, struct.pack("!I", lease_time))
    add_opt(OPT_SUBNET_MASK, ip_to_bytes(config.netmask))

    if config.routers:
        add_opt(OPT_ROUTERS, ip_to_bytes(config.routers))

    if config.broadcast:
        add_opt(OPT_BROADCAST, ip_to_bytes(config.broadcast))

    if config.dns_servers:
        dns_bytes = b"".join(ip_to_bytes(d) for d in config.dns_servers)
        add_opt(OPT_DNS, dns_bytes)

    if config.wpad_url:
        add_opt(OPT_WPAD, config.wpad_url.encode())

    options += bytes([OPT_END])

    return bytes(pkt) + bytes(options)

# =============================================================================
# PING CHECK
# =============================================================================

def ping_check(ip, timeout=1):
    """Returns True if IP responds to ping (IP is in use)."""
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), "-q", ip],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except Exception:
        return False

# =============================================================================
# DHCP SERVER
# =============================================================================

class DHCPServer:
    def __init__(self, interface, config, lease_manager):
        self.interface    = interface
        self.config       = config
        self.leases       = lease_manager
        self.server_ip    = config.server_id or config.routers
        self.broadcast_ip = config.broadcast or BROADCAST_ADDR
        self.running      = False
        self.sock         = None
        self._pending     = collections.OrderedDict()  # xid -> offered_ip, max 1024 entries

    def start(self):
        if not self.interface:
            log.error("No interface configured")
            sys.exit(1)

        # Use a raw socket at the packet level (AF_PACKET) so that DHCP
        # broadcast frames are received regardless of whether the interface
        # is a plain NIC, a bond master (802.3ad/LACP), or a bridge.
        # isc-dhcp-server uses the same approach internally via libpcap.
        try:
            self.raw_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW,
                                          socket.htons(ETH_P_IP))
            self.raw_sock.bind((self.interface, 0))
            self.raw_sock.settimeout(5.0)
        except OSError as e:
            log.error("Failed to open raw socket on %s: %s", self.interface, e)
            sys.exit(1)

        # UDP socket used only for sending replies
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("", DHCP_SERVER_PORT))

        self.running = True
        log.info("Listening on %s (DHCP port %d)", self.interface, DHCP_SERVER_PORT)

        cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        cleanup_thread.start()

        while self.running:
            try:
                frame, _ = self.raw_sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break

            # Parse Ethernet frame: dst(6) src(6) ethertype(2) = 14 bytes
            if len(frame) < 14:
                continue
            ethertype = struct.unpack_from("!H", frame, 12)[0]
            if ethertype != ETH_P_IP:
                continue

            # Parse IP header
            ip_start = 14
            if len(frame) < ip_start + 20:
                continue
            ip_ihl = (frame[ip_start] & 0x0F) * 4
            ip_proto = frame[ip_start + 9]
            if ip_proto != 17:  # UDP only
                continue

            # Parse UDP header
            udp_start = ip_start + ip_ihl
            if len(frame) < udp_start + 8:
                continue
            udp_dst = struct.unpack_from("!H", frame, udp_start + 2)[0]
            if udp_dst != DHCP_SERVER_PORT:
                continue

            # Extract DHCP payload
            dhcp_start = udp_start + 8
            data = frame[dhcp_start:]
            if len(data) < 240:
                continue

            threading.Thread(target=self._handle, args=(data, None), daemon=True).start()

    def stop(self):
        self.running = False
        if hasattr(self, 'raw_sock') and self.raw_sock:
            self.raw_sock.close()
        if self.sock:
            self.sock.close()
        log.info("pydhcpd stopped")

    def _cleanup_loop(self):
        while self.running:
            time.sleep(60)
            self.leases.cleanup_expired()

    def _handle(self, data, addr):
        pkt = parse_packet(data)
        if not pkt:
            return

        mac      = pkt["chaddr"]
        hostname = pkt["hostname"] or ""
        msg_type = pkt["msg_type"]
        log_hostname = hostname if hostname else "<no hostname>"

        if msg_type == MSG_DISCOVER:
            self._handle_discover(pkt, mac, hostname, log_hostname)

        elif msg_type == MSG_REQUEST:
            self._handle_request(pkt, mac, hostname, log_hostname)

        elif msg_type == MSG_DECLINE:
            if self.config.deny_declines:
                log.warning("DECLINE from %s ignored (deny declines)", mac)
            else:
                self.leases.release(mac)

        elif msg_type == MSG_RELEASE:
            log.info("RELEASE from %s", mac)
            self.leases.release(mac)

    def _handle_discover(self, pkt, mac, hostname, log_hostname):
        log.info("DISCOVER from %s (%s)", mac, log_hostname)

        if self.config.deny_duplicates:
            existing = self.leases.get_by_mac(mac)
            if existing and not self.leases.is_blocked(mac):
                offered_ip  = existing.ip
                lease_time  = self.config.default_lease
            else:
                offered_ip, lease_time = self.leases.allocate(mac, hostname)
        else:
            offered_ip, lease_time = self.leases.allocate(mac, hostname)

        if not offered_ip:
            log.warning("No IP available for %s", mac)
            return

        is_static = mac.lower() in self.leases.config.static_hosts
        if self.config.ping_check and not is_static and ping_check(offered_ip):
            log.warning("PING-CHECK: %s is in use, skipping offer", offered_ip)
            return

        xid_hex = pkt["xid"].hex()
        self._pending[xid_hex] = offered_ip
        if len(self._pending) > 1024:
            self._pending.popitem(last=False)

        reply = build_packet(MSG_OFFER, pkt["xid"], mac, offered_ip,
                             self.server_ip, self.config, lease_time)
        self._send(reply)
        log.info("OFFER %s → %s", mac, offered_ip)

    def _handle_request(self, pkt, mac, hostname, log_hostname):
        log.info("REQUEST from %s (%s)", mac, log_hostname)

        requested = pkt["requested_ip"]
        xid_key   = pkt["xid"].hex()

        if self.config.one_per_client:
            existing = self.leases.get_by_mac(mac)
            if existing and existing.ip != requested and not self.leases.is_blocked(mac):
                self.leases.release(mac)

        offered_ip, lease_time = self.leases.allocate(mac, hostname, requested_ip=requested)

        if not offered_ip:
            self._send_nak(pkt, mac)
            return

        self._pending.pop(xid_key, None)

        reply = build_packet(MSG_ACK, pkt["xid"], mac, offered_ip,
                             self.server_ip, self.config, lease_time)
        self._send(reply)
        log.info("ACK %s → %s (lease %ds)", mac, offered_ip, lease_time)

    def _send_nak(self, pkt, mac):
        nak = bytearray(236)
        nak[0]   = 2
        nak[4:8] = pkt["xid"]
        nak[10:12] = struct.pack("!H", 0x8000)
        opts = bytearray(DHCP_MAGIC)
        opts += bytes([OPT_MSG_TYPE, 1, MSG_NAK])
        opts += bytes([OPT_SERVER_ID, 4]) + ip_to_bytes(self.server_ip)
        opts.append(OPT_END)
        self._send(bytes(nak) + bytes(opts))
        log.info("NAK → %s", mac)

    def _send(self, data):
        try:
            self.sock.sendto(data, (self.broadcast_ip, DHCP_CLIENT_PORT))
        except OSError as e:
            log.error("Send error: %s", e)

# =============================================================================
# PID / SIGNAL
# =============================================================================

def write_pid(path):
    with open(path, "w") as f:
        f.write(str(os.getpid()))
    os.chmod(path, 0o640)

def remove_pid(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

# =============================================================================
# MAIN
# =============================================================================

def main():
    if os.geteuid() != 0:
        print("ERROR: pydhcpd must be run as root")
        sys.exit(1)

    os.makedirs(BASE_DIR, exist_ok=True)

    defaults = parse_defaults(DEFAULTS_FILE)
    interface = defaults["interface"]
    if not interface:
        log.error("No interface defined in %s (INTERFACESv4)", DEFAULTS_FILE)
        sys.exit(1)

    config = DHCPConfig()
    config.load(defaults["conf"])

    if not config.server_id:
        log.error("server-identifier not set in %s", defaults["conf"])
        sys.exit(1)

    server_ip = config.server_id or config.routers
    if not server_ip:
        log.error("Neither server-identifier nor routers defined — cannot determine server IP")
        sys.exit(1)

    lease_mgr = LeaseManager(LEASES_FILE, config,
                             daemon_user=defaults["user"],
                             daemon_group=defaults["group"])
    server    = DHCPServer(interface, config, lease_mgr)

    write_pid(defaults["pid"])

    def shutdown(signum, frame):
        log.info("Signal %d received, shutting down...", signum)
        server.stop()
        remove_pid(defaults["pid"])
        sys.exit(0)

    def reload_config(signum, frame):
        log.info("SIGHUP received — reloading configuration...")
        try:
            new_config = DHCPConfig()
            new_config.load(defaults["conf"])
            new_config._pool = []
            start_ip = new_config.pool_range_start
            end_ip   = new_config.pool_range_end
            if start_ip and end_ip:
                s = ipaddress.IPv4Address(start_ip)
                e = ipaddress.IPv4Address(end_ip)
                ip = s
                while ip <= e:
                    new_config._pool.append(str(ip))
                    ip += 1
            new_pool                 = list(new_config._pool)
            server.config            = new_config
            server.leases.config     = new_config
            server.leases.pool       = new_pool
            log.info("Configuration reloaded: %d static hosts, %d blocked MACs, %d pool IPs",
                     len(new_config.static_hosts), len(new_config.blocked_macs), len(new_config._pool))
        except Exception as e:
            log.error("Failed to reload configuration — keeping current config: %s", e)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT,  shutdown)
    signal.signal(signal.SIGHUP,  reload_config)

    log.info("pydhcpd started (pid %d, interface %s)", os.getpid(), interface)
    try:
        server.start()
    finally:
        remove_pid(defaults["pid"])


if __name__ == "__main__":
    main()
