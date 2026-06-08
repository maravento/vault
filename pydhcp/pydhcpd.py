#!/usr/bin/env python3
# pydhcpd.py — Python DHCP Daemon
# maravento.com
#
# Drop-in replacement for isc-dhcp-server.
# Reads /etc/pydhcp/pydhcpd.conf and /etc/pydhcp/default/pydhcpd,
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
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import pwd
import grp
import atexit

# =============================================================================
# PATHS
# =============================================================================

BASE_DIR        = "/etc/pydhcp"
DEFAULTS_FILE   = os.path.join(BASE_DIR, "default", "pydhcpd")
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
BROADCAST_ADDR   = "255.255.255.255"
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
OPT_MESSAGE            = 56
OPT_CLIENT_ID          = 61
OPT_WPAD               = 252
OPT_END                = 255

CONCAT_OPTS = {3, 6}

# =============================================================================
# CONFIG ERROR
# =============================================================================

class ConfigError(Exception):
    pass

# =============================================================================
# DEFAULTS PARSER
# =============================================================================

def parse_defaults(path):
    defaults = {
        "conf":      CONF_FILE,
        "pid":       PID_FILE,
        "leases":    LEASES_FILE,
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
            val = val.strip()
            if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or (val[0] == "'" and val[-1] == "'")):
                val = val[1:-1]
            val = val.strip()
            key = key.strip()
            if key == "DHCPDv4_CONF":
                defaults["conf"] = val
            elif key == "DHCPDv4_PID":
                defaults["pid"] = val
            elif key == "DHCPDv4_LEASES":
                defaults["leases"] = val
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
        self.min_lease        = 300
        self.default_lease    = 7200
        self.max_lease        = 86400

        self.pool_range_start = ""
        self.pool_range_end   = ""
        self.pool_min_lease   = 300
        self.pool_def_lease   = 7200
        self.pool_max_lease   = 86400

        self.static_hosts     = {}
        self.blocked_macs     = set()

    def load(self, path):
        if not os.path.isfile(path):
            raise ConfigError(f"Config file not found: {path}")

        with open(path) as f:
            raw = f.read()

        raw = re.sub(
            r'"(?:[^"\\]|\\.)*"|#[^\n]*',
            lambda m: m.group(0) if m.group(0).startswith('"') else '',
            raw,
        )

        self._parse(raw)
        self._validate()
        log.info("Config loaded: %d static hosts, %d blocked MACs",
                 len(self.static_hosts), len(self.blocked_macs))

    def _validate(self):
        if self.pool_range_start and self.pool_range_end:
            try:
                s = ipaddress.IPv4Address(self.pool_range_start)
                e = ipaddress.IPv4Address(self.pool_range_end)
                if s > e:
                    raise ConfigError(f"Pool range start ({s}) is greater than end ({e})")
                if self.subnet and self.netmask:
                    net = ipaddress.IPv4Network(f"{self.subnet}/{self.netmask}", strict=False)
                    if s not in net or e not in net:
                        raise ConfigError(f"Pool range {s}\u2013{e} is outside subnet {net}")
            except ValueError as err:
                raise ConfigError(f"Invalid pool range address: {err}") from err

        seen_ips = {}
        for mac, ip in self.static_hosts.items():
            if ip in seen_ips:
                raise ConfigError(
                    f"Duplicate static IP {ip} assigned to {seen_ips[ip]} and {mac}")
            seen_ips[ip] = mac

    @staticmethod
    def _balanced_braces(text, start):
        depth = 1
        i = start
        in_string = False
        escape_next = False
        string_char = None
        while i < len(text):
            c = text[i]

            if not escape_next and (c == '"' or c == "'"):
                if not in_string:
                    in_string = True
                    string_char = c
                elif c == string_char:
                    in_string = False

            if not in_string:
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0:
                        return text[start:i]

            escape_next = (c == '\\' and not escape_next)
            i += 1
        return None

    def _parse(self, raw):
        if re.search(r'\bclass\s+"blockdhcp"', raw):
            log.warning(
                "'class \"blockdhcp\" { match ... }' directive is not enforced — "
                "use 'subclass \"blockdhcp\" 1:MAC;' for effective MAC blocking"
            )

        self.authoritative   = bool(re.search(r'\bauthoritative\s*;', raw))
        self.deny_duplicates = bool(re.search(r'\bdeny\s+duplicates\s*;', raw))
        self.one_per_client  = bool(re.search(r'\bone-lease-per-client\s+true\s*;', raw))
        self.deny_declines   = bool(re.search(r'\bdeny\s+declines\s*;', raw))
        self.deny_client_upd = bool(re.search(r'\bdeny\s+client-updates\s*;', raw))
        self.ping_check      = bool(re.search(r'\bping-check\s+true\s*;', raw))

        m = re.search(r'\bserver-identifier\s+([\d.]+)\s*;', raw)
        if m:
            self.server_id = m.group(1)

        for m in re.finditer(
            r'\bhost\s+\S+\s*\{(.*?)\}',
            raw, re.IGNORECASE | re.DOTALL
        ):
            block = m.group(1)
            mac_m = re.search(r'hardware\s+ethernet\s+([\da-f:]+)\s*;', block, re.IGNORECASE)
            ip_m  = re.search(r'fixed-address\s+([\d.]+)\s*;', block, re.IGNORECASE)
            if mac_m and ip_m:
                self.static_hosts[mac_m.group(1).lower()] = ip_m.group(1)

        for m in re.finditer(
            r'\bsubclass\s+"blockdhcp"\s+1:([\da-f:]+)\s*;',
            raw, re.IGNORECASE
        ):
            self.blocked_macs.add(m.group(1).lower())

        m = re.search(r'\bsubnet\s+([\d.]+)\s+netmask\s+([\d.]+)\s*\{', raw)
        if m:
            subnet_body = self._balanced_braces(raw, m.end())
            if subnet_body is not None:
                self.subnet  = m.group(1)
                self.netmask = m.group(2)
                self._parse_subnet(subnet_body)

    def _parse_subnet(self, body):
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
                    try:
                        ipaddress.IPv4Address(entry)
                        resolved.append(entry)
                    except ValueError:
                        log.warning("Invalid DNS server IP: %s (skipped)", entry)
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
            self.min_lease = int(m.group(1))

        m = re.search(r'default-lease-time\s+(\d+)\s*;', body)
        if m:
            self.default_lease = int(m.group(1))

        m = re.search(r'max-lease-time\s+(\d+)\s*;', body)
        if m:
            self.max_lease = int(m.group(1))

        pool_m = re.search(r'\bpool\s*\{', body)
        pool = self._balanced_braces(body, pool_m.end()) if pool_m else None
        if pool is not None:
            m = re.search(r'range\s+([\d.]+)\s+([\d.]+)\s*;', pool)
            if m:
                self.pool_range_start = m.group(1)
                self.pool_range_end   = m.group(2)

            m = re.search(r'min-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_min_lease = int(m.group(1))

            m = re.search(r'default-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_def_lease = int(m.group(1))

            m = re.search(r'max-lease-time\s+(\d+)\s*;', pool)
            if m:
                self.pool_max_lease = int(m.group(1))

# =============================================================================
# LEASE MANAGER
# =============================================================================

class Lease:
    def __init__(self, ip, mac, hostname, start, end, binding="active"):
        self.ip       = ip
        self.mac      = mac
        self.hostname = re.sub(r'[\x00-\x1f\x7f"\\;{}]', '', str(hostname))[:64]
        self.start    = start
        self.end      = end
        self.binding  = binding

    def is_expired(self):
        return time.time() > self.end

    def to_conf(self):
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
        self.lock   = threading.RLock()
        self.leases = {}
        self._alloc_counter = 0
        self._quarantine = {}
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
            start_m = re.search(r'starts\s+\d+\s+([\d/]+ [\d:]+)\s*;', body)
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

            if start_m:
                try:
                    start = datetime.strptime(start_m.group(1), "%Y/%m/%d %H:%M:%S").replace(
                        tzinfo=timezone.utc).timestamp()
                except ValueError:
                    start = time.time()
            else:
                start = time.time()

            lease = Lease(ip, mac, hostname, start, end, binding)
            if not lease.is_expired():
                self.leases[ip] = lease

        log.info("Leases loaded: %d entries", len(self.leases))

    @staticmethod
    def _compute_pool(config):
        pool = set()
        if not config.pool_range_start or not config.pool_range_end:
            return pool
        try:
            start = ipaddress.IPv4Address(config.pool_range_start)
            end = ipaddress.IPv4Address(config.pool_range_end)

            network_addr = None
            broadcast_addr = None
            if config.subnet and config.netmask:
                try:
                    net = ipaddress.IPv4Network(f"{config.subnet}/{config.netmask}", strict=False)
                    network_addr = str(net.network_address)
                    broadcast_addr = str(net.broadcast_address)
                except ValueError:
                    pass

            ip = start
            while ip <= end:
                ip_str = str(ip)
                exclude = False
                if network_addr and broadcast_addr:
                    if ip_str == network_addr or ip_str == broadcast_addr:
                        exclude = True
                elif ip_str.endswith('.0') or ip_str.endswith('.255'):
                    exclude = True
                if not exclude:
                    pool.add(ip_str)
                ip += 1
        except ValueError as e:
            log.error("Invalid pool range: %s", e)
        return pool

    def _build_pool(self):
        with self.lock:
            self.pool = self._compute_pool(self.config)

    @staticmethod
    def _ip_key(ip):
        return tuple(int(o) for o in ip.split('.'))

    def get_by_mac(self, mac):
        mac = mac.lower()
        with self.lock:
            for lease in self.leases.values():
                if lease.mac == mac and not lease.is_expired():
                    return lease
        return None

    def get_static(self, mac):
        mac = mac.lower()
        with self.lock:
            return self.config.static_hosts.get(mac)

    def is_blocked(self, mac):
        mac = mac.lower()
        with self.lock:
            return mac in self.config.blocked_macs

    def quarantine_ip(self, ip, duration=3600):
        with self.lock:
            self._quarantine[ip] = time.time() + duration

    def allocate(self, mac, hostname, requested_ip=None):
        mac = mac.lower()

        with self.lock:
            static_ip = self.config.static_hosts.get(mac)
            if static_ip:
                return static_ip, self.config.max_lease

            if mac in self.config.blocked_macs:
                return None, None

            if requested_ip and requested_ip != "0.0.0.0":
                if requested_ip in self.pool:
                    existing_lease = self.leases.get(requested_ip)
                    if not existing_lease or existing_lease.is_expired():
                        self._create_lease(requested_ip, mac, hostname, self.config.pool_def_lease)
                        return requested_ip, self.config.pool_def_lease
                    elif existing_lease.mac == mac:
                        self._create_lease(requested_ip, mac, hostname, self.config.pool_def_lease)
                        return requested_ip, self.config.pool_def_lease
                    else:
                        return None, None

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
        active_ips = {ip for ip, lease in self.leases.items() if not lease.is_expired()}
        now = time.time()
        quarantined = {ip for ip, exp in self._quarantine.items() if exp > now}
        free = self.pool - active_ips - static_ips - quarantined
        if not free:
            return None
        sorted_free = sorted(free, key=self._ip_key)
        idx = self._alloc_counter % len(sorted_free)
        self._alloc_counter = (idx + 1) % (2**16)
        return sorted_free[idx]

    def _create_lease(self, ip, mac, hostname, duration):
        now = time.time()
        lease = Lease(ip, mac, hostname, now, now + duration)
        with self.lock:
            self.leases[ip] = lease
            snapshot = dict(self.leases)
        self._save_snapshot(snapshot)

    def _save_snapshot(self, snapshot):
        tmp_path = self.path + ".tmp"
        with open(tmp_path, "w") as f:
            for lease in snapshot.values():
                f.write(lease.to_conf())
                f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        if self._uid is not None and self._gid is not None:
            try:
                os.chown(tmp_path, self._uid, self._gid)
            except OSError as e:
                log.warning("Cannot chown %s to %d:%d: %s",
                            tmp_path, self._uid, self._gid, e)
        os.chmod(tmp_path, 0o640)
        os.replace(tmp_path, self.path)

    def release(self, mac):
        mac = mac.lower()
        with self.lock:
            to_del = [ip for ip, l in self.leases.items() if l.mac == mac]
            for ip in to_del:
                del self.leases[ip]
            if to_del:
                snapshot = dict(self.leases)
            else:
                snapshot = None
        if snapshot is not None:
            self._save_snapshot(snapshot)

    def cleanup_expired(self):
        with self.lock:
            expired = [ip for ip, l in self.leases.items() if l.is_expired()]
            for ip in expired:
                log.info("Lease expired: %s", ip)
                del self.leases[ip]
            if expired:
                snapshot = dict(self.leases)
            else:
                snapshot = None
            now = time.time()
            stale = [ip for ip, exp in self._quarantine.items() if exp <= now]
            for ip in stale:
                del self._quarantine[ip]
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
    if len(data) < 240:
        return None

    pkt = {}
    pkt["op"]    = data[0]
    pkt["htype"] = data[1]
    if pkt["htype"] != 1:
        return None
    pkt["hlen"]  = data[2]
    if pkt["hlen"] != 6:
        return None

    pkt["hops"] = data[3]
    if pkt["hops"] >= 16:
        return None

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
    data_len = len(data)
    while i < data_len:
        opt = data[i]
        if opt == OPT_END:
            break
        if opt == 0:
            i += 1
            continue
        if i + 1 >= data_len:
            break
        length = data[i + 1]

        if i + 2 + length > data_len:
            log.warning("Malformed DHCP option %d: length %d exceeds packet", opt, length)
            break

        value = data[i + 2: i + 2 + length]

        if opt in CONCAT_OPTS:
            pkt["options"][opt] = pkt["options"].get(opt, b"") + value
        else:
            pkt["options"][opt] = value
        i += 2 + length

    msg_type_opt = pkt["options"].get(OPT_MSG_TYPE, b"\x00")
    if len(msg_type_opt) == 0:
        pkt["msg_type"] = 0
    else:
        pkt["msg_type"] = msg_type_opt[0]
    raw_hostname = pkt["options"].get(12, b"").decode("ascii", errors="replace").strip("\x00").strip()
    pkt["hostname"] = re.sub(r'[\x00-\x1f\x7f"\\;{}]', '', raw_hostname).strip()
    opt_req_ip = pkt["options"].get(OPT_REQUESTED_IP, b"\x00\x00\x00\x00")
    pkt["requested_ip"] = bytes_to_ip(opt_req_ip) if len(opt_req_ip) == 4 else "0.0.0.0"

    return pkt


def build_packet(msg_type, xid, mac_str, offered_ip, server_ip, config, lease_time,
                 broadcast=True):
    if not config.netmask:
        log.error("Cannot build packet: netmask not configured")
        return b""

    try:
        mac_bytes = bytes(int(x, 16) for x in mac_str.split(":"))
        if len(mac_bytes) != 6:
            raise ValueError("Invalid MAC length")
    except ValueError:
        log.error("Invalid MAC address format: %s", mac_str)
        return b""

    pkt = bytearray(236)
    pkt[0]  = 2
    pkt[1]  = 1
    pkt[2]  = 6
    pkt[3]  = 0
    pkt[4:8] = xid
    pkt[10:12] = struct.pack("!H", 0x8000 if broadcast else 0)
    pkt[16:20] = ip_to_bytes(offered_ip)
    pkt[20:24] = ip_to_bytes(server_ip)
    pkt[28:34] = mac_bytes

    options = bytearray()
    options += DHCP_MAGIC

    def add_opt(code, value):
        nonlocal options
        options += bytes([code, len(value)]) + value

    add_opt(OPT_MSG_TYPE,  bytes([msg_type]))
    add_opt(OPT_SERVER_ID, ip_to_bytes(server_ip))
    if msg_type != MSG_INFORM:
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

_PING_CACHE_TTL = 120
_ping_cache_lock = threading.Lock()
_ping_cache = {}
_ping_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="ping")

def _shutdown_ping_executor():
    _ping_executor.shutdown(wait=False)
atexit.register(_shutdown_ping_executor)

def ping_check(ip, timeout=1):
    now = time.time()
    with _ping_cache_lock:
        entry = _ping_cache.get(ip)
        if entry and entry[1] > now:
            return entry[0]
        for k in list(_ping_cache.keys()):
            if _ping_cache[k][1] <= now:
                del _ping_cache[k]
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), "-q", ip],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1.5,
        )
        alive = result.returncode == 0
    except Exception:
        alive = False
    with _ping_cache_lock:
        _ping_cache[ip] = (alive, now + _PING_CACHE_TTL)
    return alive

# =============================================================================
# DHCP SERVER
# =============================================================================

class DHCPServer:
    MAX_INFLIGHT = 256

    def __init__(self, interface, config, lease_manager):
        self.interface    = interface
        self.config       = config
        self.leases       = lease_manager
        self.server_ip    = config.server_id or config.routers
        if not self.server_ip:
            raise ValueError("DHCPServer: neither server-identifier nor routers configured")
        self.broadcast_ip = config.broadcast or BROADCAST_ADDR
        self.running      = False
        self.sock         = None
        self._pending     = collections.OrderedDict()
        self._pending_lock = threading.Lock()
        self._thread_pool  = ThreadPoolExecutor(max_workers=32)
        self._inflight     = threading.Semaphore(self.MAX_INFLIGHT)
        self._dropped      = 0
        self._config_lock = threading.RLock()

    def apply_config(self, new_config):
        with self._config_lock:
            new_pool = LeaseManager._compute_pool(new_config)
            with self.leases.lock:
                self.config        = new_config
                self.leases.config = new_config
                self.leases.pool   = new_pool
            self.server_ip    = new_config.server_id or new_config.routers
            self.broadcast_ip = new_config.broadcast or BROADCAST_ADDR

    def start(self):
        if not self.interface:
            log.error("No interface configured")
            sys.exit(1)

        try:
            self.raw_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW,
                                          socket.htons(ETH_P_IP))
            self.raw_sock.bind((self.interface, 0))
            self.raw_sock.settimeout(5.0)
        except OSError as e:
            log.error("Failed to open raw socket on %s: %s", self.interface, e)
            sys.exit(1)

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

            if len(frame) < 14:
                continue
            ethertype = struct.unpack_from("!H", frame, 12)[0]
            if ethertype != ETH_P_IP:
                continue

            ip_start = 14
            if len(frame) < ip_start + 20:
                continue
            ip_ihl = (frame[ip_start] & 0x0F) * 4
            ip_proto = frame[ip_start + 9]
            if ip_proto != 17:
                continue

            udp_start = ip_start + ip_ihl
            if len(frame) < udp_start + 8:
                continue
            udp_dst = struct.unpack_from("!H", frame, udp_start + 2)[0]
            if udp_dst != DHCP_SERVER_PORT:
                continue

            dhcp_start = udp_start + 8
            data = frame[dhcp_start:]
            if len(data) < 240:
                continue

            src_mac = mac_bytes_to_str(frame[6:12])

            if not self._inflight.acquire(blocking=False):
                self._dropped += 1
                if self._dropped % 100 == 1:
                    log.warning("Worker backlog full (%d) — dropping packets "
                                "(total dropped: %d)", self.MAX_INFLIGHT, self._dropped)
                continue
            try:
                self._thread_pool.submit(self._handle_packet, data, src_mac)
            except RuntimeError:
                self._inflight.release()

    def _handle_packet(self, data, src_mac):
        try:
            self._handle(data, src_mac)
        except Exception as e:
            log.exception("Unhandled error in worker: %s", e)
        finally:
            self._inflight.release()

    def stop(self):
        self.running = False
        self._thread_pool.shutdown(wait=False)
        if hasattr(self, 'raw_sock') and self.raw_sock:
            self.raw_sock.close()
        if self.sock:
            self.sock.close()
        log.info("pydhcpd stopped")

    def _cleanup_loop(self):
        while self.running:
            time.sleep(60)
            self.leases.cleanup_expired()

    def _handle(self, data, src_mac):
        pkt = parse_packet(data)
        if not pkt:
            return

        dhcp_giaddr = pkt.get("giaddr", "0.0.0.0")

        if dhcp_giaddr == "0.0.0.0":
            if pkt["chaddr"] != src_mac:
                log.warning("chaddr spoofing detected: frame src=%s chaddr=%s — dropped",
                            src_mac, pkt["chaddr"])
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
            with self._config_lock:
                config_deny_declines = self.config.deny_declines

            if config_deny_declines:
                log.warning("DECLINE from %s ignored (deny declines)", mac)
            else:
                declined = self.leases.get_by_mac(mac)
                if declined:
                    self.leases.quarantine_ip(declined.ip)
                    log.info("DECLINE from %s: IP %s quarantined", mac, declined.ip)
                self.leases.release(mac)

        elif msg_type == MSG_RELEASE:
            log.info("RELEASE from %s", mac)
            self.leases.release(mac)

        elif msg_type == MSG_INFORM:
            self._handle_inform(pkt, mac, hostname, log_hostname)

        else:
            log.debug("Unknown message type %d from %s", msg_type, mac)

    def _handle_inform(self, pkt, mac, hostname, log_hostname):
        log.info("INFORM from %s (%s)", mac, log_hostname)
        use_broadcast = self._should_broadcast(pkt)

        with self._config_lock:
            config_netmask = self.config.netmask
            config_routers = self.config.routers
            config_broadcast = self.config.broadcast
            config_dns_servers = self.config.dns_servers
            config_wpad_url = self.config.wpad_url

        if not config_netmask:
            log.error("Cannot build INFORM packet: netmask not configured")
            return

        try:
            mac_bytes = bytes(int(x, 16) for x in mac.split(":"))
            if len(mac_bytes) != 6:
                raise ValueError("Invalid MAC length")
        except ValueError:
            log.error("Invalid MAC address format: %s", mac)
            return

        pkt_buf = bytearray(236)
        pkt_buf[0]  = 2
        pkt_buf[1]  = 1
        pkt_buf[2]  = 6
        pkt_buf[3]  = 0
        pkt_buf[4:8] = pkt["xid"]
        pkt_buf[10:12] = struct.pack("!H", 0x8000 if use_broadcast else 0)
        pkt_buf[16:20] = ip_to_bytes(pkt.get("ciaddr", "0.0.0.0"))
        pkt_buf[20:24] = ip_to_bytes(self.server_ip)
        pkt_buf[28:34] = mac_bytes

        options = bytearray()
        options += DHCP_MAGIC

        def add_opt(code, value):
            nonlocal options
            options += bytes([code, len(value)]) + value

        add_opt(OPT_MSG_TYPE, bytes([MSG_ACK]))
        add_opt(OPT_SERVER_ID, ip_to_bytes(self.server_ip))
        add_opt(OPT_SUBNET_MASK, ip_to_bytes(config_netmask))

        if config_routers:
            add_opt(OPT_ROUTERS, ip_to_bytes(config_routers))

        if config_broadcast:
            add_opt(OPT_BROADCAST, ip_to_bytes(config_broadcast))

        if config_dns_servers:
            dns_bytes = b"".join(ip_to_bytes(d) for d in config_dns_servers)
            add_opt(OPT_DNS, dns_bytes)

        if config_wpad_url:
            add_opt(OPT_WPAD, config_wpad_url.encode())

        options += bytes([OPT_END])

        reply = bytes(pkt_buf) + bytes(options)
        self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))

    def _handle_discover(self, pkt, mac, hostname, log_hostname):
        log.info("DISCOVER from %s (%s)", mac, log_hostname)

        with self._config_lock:
            config_deny_duplicates = self.config.deny_duplicates
            config_ping_check = self.config.ping_check
            config_default_lease = self.config.default_lease

        if config_deny_duplicates:
            existing = self.leases.get_by_mac(mac)
            if existing and not self.leases.is_blocked(mac):
                offered_ip  = existing.ip
                lease_time  = config_default_lease
            else:
                offered_ip, lease_time = self.leases.allocate(mac, hostname)
        else:
            offered_ip, lease_time = self.leases.allocate(mac, hostname)

        if not offered_ip:
            log.warning("No IP available for %s", mac)
            return

        is_static = bool(self.leases.get_static(mac))
        existing_lease = self.leases.get_by_mac(mac)
        is_own_ip = existing_lease and existing_lease.ip == offered_ip

        if config_ping_check and not is_static and not is_own_ip:
            future = _ping_executor.submit(ping_check, offered_ip)
            try:
                alive = future.result(timeout=2.0)
            except Exception:
                alive = False
            if alive:
                log.warning("PING-CHECK: %s is in use — quarantined", offered_ip)
                self.leases.quarantine_ip(offered_ip, duration=3600)
                self.leases.release(mac)
                return

        xid_hex = pkt["xid"].hex()
        with self._pending_lock:
            self._pending[xid_hex] = offered_ip
            if len(self._pending) > 1024:
                self._pending.popitem(last=False)

        use_broadcast = self._should_broadcast(pkt)
        reply = build_packet(MSG_OFFER, pkt["xid"], mac, offered_ip,
                             self.server_ip, self.config, lease_time,
                             broadcast=use_broadcast)
        if reply:
            self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))
            log.info("OFFER %s → %s", mac, offered_ip)

    def _handle_request(self, pkt, mac, hostname, log_hostname):
        log.info("REQUEST from %s (%s)", mac, log_hostname)

        requested = pkt["requested_ip"]
        ciaddr    = pkt["ciaddr"]
        xid_key   = pkt["xid"].hex()

        if requested and requested != "0.0.0.0":
            target_ip = requested
        elif ciaddr and ciaddr != "0.0.0.0":
            target_ip = ciaddr
        else:
            existing = self.leases.get_by_mac(mac)
            target_ip = existing.ip if existing else None

        server_id_opt = pkt["options"].get(OPT_SERVER_ID, b"")
        if len(server_id_opt) == 4:
            selected_server = bytes_to_ip(server_id_opt)
            if selected_server != self.server_ip:
                log.debug("REQUEST from %s is for server %s, ignoring", mac, selected_server)
                return

        with self._pending_lock:
            pending_ip = self._pending.get(xid_key)
        if pending_ip and target_ip and target_ip != pending_ip:
            log.info("NAK (SELECTING mismatch) → %s requested %s but we offered %s",
                     mac, target_ip, pending_ip)
            self._send_nak(pkt, mac, "Requested IP does not match offer")
            return

        with self._config_lock:
            config_auth = self.config.authoritative
            config_one_per_client = self.config.one_per_client
            config_pool_def_lease = self.config.pool_def_lease

        if config_auth and target_ip:
            static_ip = self.leases.get_static(mac)
            if static_ip and target_ip != static_ip:
                log.info("NAK (authoritative) → %s requested %s but assigned %s",
                         mac, target_ip, static_ip)
                self._send_nak(pkt, mac, "Not authorized for this IP")
                return

        with self.leases.lock:
            if config_one_per_client and target_ip:
                existing = self.leases.get_by_mac(mac)
                if existing and existing.ip != target_ip and not self.leases.is_blocked(mac):
                    self.leases.release(mac)

            offered_ip, lease_time = self.leases.allocate(mac, hostname, requested_ip=target_ip)

        if not offered_ip:
            self._send_nak(pkt, mac, "No address available")
            return

        with self._pending_lock:
            self._pending.pop(xid_key, None)

        use_broadcast = self._should_broadcast(pkt)
        reply = build_packet(MSG_ACK, pkt["xid"], mac, offered_ip,
                             self.server_ip, self.config, lease_time,
                             broadcast=use_broadcast)
        if reply:
            self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))
            log.info("ACK %s → %s (lease %ds)", mac, offered_ip, lease_time)

    def _send_nak(self, pkt, mac, reason=None):
        nak = bytearray(236)
        nak[0]   = 2
        nak[4:8] = pkt["xid"]
        nak[10:12] = struct.pack("!H", 0x8000)
        try:
            nak[28:34] = bytes(int(x, 16) for x in mac.split(":"))
        except (ValueError, IndexError):
            pass
        opts = bytearray(DHCP_MAGIC)
        opts += bytes([OPT_MSG_TYPE, 1, MSG_NAK])
        opts += bytes([OPT_SERVER_ID, 4]) + ip_to_bytes(self.server_ip)
        if reason:
            msg = reason.encode("ascii", errors="replace")[:255]
            opts += bytes([OPT_MESSAGE, len(msg)]) + msg
        opts.append(OPT_END)
        self._send(bytes(nak) + bytes(opts),
                   giaddr=pkt.get("giaddr", "0.0.0.0"),
                   ciaddr="0.0.0.0")
        log.info("NAK → %s%s", mac, f" ({reason})" if reason else "")

    @staticmethod
    def _should_broadcast(pkt):
        return bool(pkt.get("flags", 0) & 0x8000)

    def _send(self, data, giaddr="0.0.0.0", ciaddr="0.0.0.0"):
        if giaddr and giaddr != "0.0.0.0":
            dest = (giaddr, DHCP_SERVER_PORT)
        elif ciaddr and ciaddr != "0.0.0.0":
            dest = (ciaddr, DHCP_CLIENT_PORT)
        else:
            dest = (self.broadcast_ip, DHCP_CLIENT_PORT)
        try:
            self.sock.sendto(data, dest)
        except OSError as e:
            log.error("Send error: %s", e)

# =============================================================================
# PID / SIGNAL
# =============================================================================

def write_pid(path):
    if os.path.exists(path):
        try:
            with open(path, 'r') as f:
                old_pid = int(f.read().strip())
            os.kill(old_pid, 0)
            log.warning("PID file %s exists with running process %d, overwriting", path, old_pid)
        except (ValueError, OSError, ProcessLookupError):
            pass
    with open(path, "w") as f:
        f.write(str(os.getpid()))
    os.chmod(path, 0o640)

def remove_pid(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

def test_config(config_path):
    try:
        config = DHCPConfig()
        config.load(config_path)
        print(f"Configuration OK: {len(config.static_hosts)} static hosts, {len(config.blocked_macs)} blocked MACs")
        return True
    except ConfigError as e:
        print(f"Configuration error: {e}")
        return False

# =============================================================================
# MAIN
# =============================================================================

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-t", "--test"):
        config_path = sys.argv[2] if len(sys.argv) > 2 else CONF_FILE
        sys.exit(0 if test_config(config_path) else 1)

    os.makedirs(BASE_DIR, exist_ok=True)

    defaults = parse_defaults(DEFAULTS_FILE)
    interface = defaults["interface"]
    if not interface:
        log.error("No interface defined in %s (INTERFACESv4)", DEFAULTS_FILE)
        sys.exit(1)
    if not os.path.isdir(f"/sys/class/net/{interface}"):
        log.error("Interface '%s' does not exist on this system", interface)
        sys.exit(1)

    config = DHCPConfig()
    try:
        config.load(defaults["conf"])
    except ConfigError as e:
        log.error("Configuration error: %s", e)
        sys.exit(1)

    if not config.server_id:
        log.error("server-identifier not set in %s", defaults["conf"])
        sys.exit(1)

    lease_mgr = LeaseManager(defaults["leases"], config,
                             daemon_user=defaults["user"],
                             daemon_group=defaults["group"])
    server    = DHCPServer(interface, config, lease_mgr)

    write_pid(defaults["pid"])

    def signal_shutdown(signum, frame):
        log.info("Signal %d received, shutting down...", signum)
        _shutdown_ping_executor()
        server.stop()
        remove_pid(defaults["pid"])
        sys.exit(0)

    def reload_config(signum, frame):
        log.info("SIGHUP received — reloading configuration...")
        try:
            new_config = DHCPConfig()
            new_config.load(defaults["conf"])
            if not new_config.server_id:
                log.error("Reloaded config has no server-identifier — keeping current config")
                return
            server.apply_config(new_config)
            log.info("Configuration reloaded: %d static hosts, %d blocked MACs, %d pool IPs",
                     len(new_config.static_hosts), len(new_config.blocked_macs), len(server.leases.pool))
        except Exception as e:
            log.error("Failed to reload configuration — keeping current config: %s", e)

    signal.signal(signal.SIGTERM, signal_shutdown)
    signal.signal(signal.SIGINT,  signal_shutdown)
    signal.signal(signal.SIGHUP,  reload_config)

    log.info("pydhcpd started (pid %d, interface %s)", os.getpid(), interface)
    try:
        server.start()
    finally:
        remove_pid(defaults["pid"])


if __name__ == "__main__":
    main()
