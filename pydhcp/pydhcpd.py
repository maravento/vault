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
import tempfile

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

_TEST_MODE = len(sys.argv) > 1 and sys.argv[1] in ("-t", "--test")

_log_handlers = [logging.StreamHandler(sys.stdout)]
if not _TEST_MODE:
    try:
        _log_handlers.insert(0, logging.FileHandler(LOG_FILE))
    except OSError as e:
        sys.stderr.write(
            f"WARNING: cannot open {LOG_FILE} for writing ({e}); "
            "logging to stdout only\n")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=_log_handlers,
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
OPT_PAD                = 0
DHCP_MIN_PACKET_SIZE   = 300  # RFC 951/2131: minimum BOOTP payload some
                              # relays/clients expect; anything shorter may
                              # be silently dropped by strict implementations.

def _pad_to_min_bootp(packet):
    if len(packet) < DHCP_MIN_PACKET_SIZE:
        packet = packet + bytes(DHCP_MIN_PACKET_SIZE - len(packet))
    return packet

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

        self.cleanup_interval = 60

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
                for h_mac, h_ip in self.static_hosts.items():
                    try:
                        if s <= ipaddress.IPv4Address(h_ip) <= e:
                            raise ConfigError(
                                f"Static host {h_mac} IP {h_ip} overlaps pool range {s}\u2013{e}")
                    except ValueError:
                        pass
            except ValueError as err:
                raise ConfigError(f"Invalid pool range address: {err}") from err

        seen_ips = {}
        for mac, ip in self.static_hosts.items():
            if ip in seen_ips:
                raise ConfigError(
                    f"Duplicate static IP {ip} assigned to {seen_ips[ip]} and {mac}")
            seen_ips[ip] = mac

        if self.wpad_url and len(self.wpad_url.encode()) > 255:
            raise ConfigError(
                f"wpad URL is {len(self.wpad_url.encode())} bytes; DHCP option 252 max is 255")
        if len(self.dns_servers) > 63:
            raise ConfigError(
                f"{len(self.dns_servers)} DNS servers configured; DHCP option 6 holds at most 63")

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
        m = re.search(r'\bcleanup-interval\s+(\d+)\s*;', raw)
        if m:
            self.cleanup_interval = max(5, int(m.group(1)))

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
                    # Hostnames are not accepted: resolving them blocks the main
                    # thread (including SIGHUP reload) for an unbounded time.
                    log.warning("DNS server must be an IP address, not a hostname: "
                                "%s (skipped)", entry)
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
        self.hostname = re.sub(r'[\x00-\x1f\x7f"\\;{}%]', '', str(hostname))[:64]
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
    # Token-bucket rate-limit for DISCOVER/REQUEST: at most this many new lease
    # allocations per MAC within the sliding window, to limit pool exhaustion
    # by an attacker rotating MACs.
    _RATE_LIMIT_WINDOW = 60   # seconds
    _RATE_LIMIT_MAX    = 5    # allocations per window per MAC

    # A DISCOVER only ever earns a short-lived, in-memory-only reservation —
    # never a full-duration lease. It's promoted to a real lease only when
    # the matching REQUEST arrives. This keeps a DISCOVER flood (trivially
    # forged, one MAC per packet) from being able to hold pool IPs hostage
    # for hours; the reservation self-expires in seconds regardless of
    # whether the client ever follows up.
    _RESERVATION_TTL = 30     # seconds

    def __init__(self, path, config, daemon_user="pydhcpd", daemon_group="pydhcpd"):
        self.path   = path
        self.config = config
        self.lock   = threading.RLock()
        self._write_lock = threading.Lock()
        self.leases = {}
        self._reservations = {}  # ip -> (mac, expiry_ts); provisional, never persisted
        self._alloc_counter = 0
        self._quarantine = {}
        self._rate    = {}   # mac -> deque of timestamps
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

    def allocate(self, mac, hostname, requested_ip=None, hint_ip=None, src_mac=None,
                 persist=True, provisional=False):
        mac = mac.lower()
        # Rate-limit per client MAC (chaddr) so that multiple clients behind
        # the same relay do not share a single rate-limit bucket.
        rate_key = mac
        # Captured inside the lock, written to disk after the lock is released
        # so fsync does not block concurrent allocations. Provisional grants
        # (DISCOVER) never touch self.leases or disk at all — see _grant().
        snapshot_to_save = None
        try:
            with self.lock:
                static_ip = self.config.static_hosts.get(mac)
                if static_ip:
                    return static_ip, self.config.max_lease, None

                if mac in self.config.blocked_macs:
                    return None, None, "deny members of blockdhcp"

                # Sliding-window rate-limit: reject new allocations from MACs that
                # have already consumed their quota in the last window.
                now = time.time()
                window_start = now - self._RATE_LIMIT_WINDOW
                bucket = self._rate.setdefault(rate_key, collections.deque())
                while bucket and bucket[0] < window_start:
                    bucket.popleft()
                # A REQUEST that renews the exact IP this MAC already holds
                # (active lease, or a live reservation from its own DISCOVER)
                # never consumes a new pool address, so the allocation
                # rate-limit — which exists only to throttle NEW allocations —
                # must not reject it. This mirrors the counter logic below,
                # which already declines to count such requests toward the quota.
                renewing_own_ip = False
                if requested_ip and requested_ip != "0.0.0.0":
                    held = self.leases.get(requested_ip)
                    if held and not held.is_expired() and held.mac == mac:
                        renewing_own_ip = True
                    else:
                        resv = self._reservations.get(requested_ip)
                        if resv and resv[0] == mac and resv[1] > now:
                            renewing_own_ip = True
                if len(bucket) >= self._RATE_LIMIT_MAX and not renewing_own_ip:
                    log.warning("Rate-limit: %s exceeded %d allocations in %ds — dropped",
                                rate_key, self._RATE_LIMIT_MAX, self._RATE_LIMIT_WINDOW)
                    return None, None, "rate limited"

                def _held_by_other(ip):
                    lease = self.leases.get(ip)
                    if lease and not lease.is_expired() and lease.mac != mac:
                        return True
                    resv = self._reservations.get(ip)
                    if resv and resv[1] > now and resv[0] != mac:
                        return True
                    return False

                def _grant(ip):
                    nonlocal snapshot_to_save
                    if provisional:
                        # Short-lived, in-memory-only hold — never a real
                        # lease, never persisted, self-expires in seconds.
                        self._reservations[ip] = (mac, now + self._RESERVATION_TTL)
                    else:
                        # Enforce one pool lease per MAC: drop any other pool
                        # lease this MAC already holds so granting `ip` never
                        # leaves two leases alive for the same client.
                        for other_ip, other_lease in list(self.leases.items()):
                            if (other_lease.mac == mac and other_ip != ip
                                    and other_ip in self.pool):
                                del self.leases[other_ip]
                        self._reservations.pop(ip, None)
                        snapshot_to_save = self._create_lease_locked(ip, mac, hostname, self.config.pool_def_lease)

                # requested_ip (REQUEST, option 50) is a hard requirement:
                # if it cannot be honored, the caller must NAK. hint_ip
                # (DISCOVER, option 50) is only a preference: if it cannot
                # be honored, fall through to normal pool selection instead
                # of failing the DISCOVER outright.
                is_hard = bool(requested_ip and requested_ip != "0.0.0.0")
                if is_hard:
                    candidate = requested_ip
                elif hint_ip and hint_ip != "0.0.0.0":
                    candidate = hint_ip
                else:
                    candidate = None

                if candidate and candidate in self.pool:
                    static_ips = set(self.config.static_hosts.values())
                    reserved_for_other = (candidate in static_ips
                                          and self.config.static_hosts.get(mac) != candidate)
                    if reserved_for_other:
                        if is_hard:
                            return None, None, "IP reserved for static host"
                        # soft hint pointing at someone else's static IP: ignore
                        # it and fall through to normal pool selection below.
                    elif not _held_by_other(candidate):
                        already_held_by_self = (
                            (self.leases.get(candidate) and self.leases[candidate].mac == mac
                             and not self.leases[candidate].is_expired())
                            or (self._reservations.get(candidate, (None, 0))[0] == mac
                                and self._reservations.get(candidate, (None, 0))[1] > now))
                        if not already_held_by_self:
                            bucket.append(now)
                        _grant(candidate)
                        return candidate, self.config.pool_def_lease, None
                    elif is_hard:
                        existing_lease = self.leases.get(candidate)
                        if existing_lease and not existing_lease.is_expired():
                            return None, None, "requested IP in use"
                        return None, None, "pool exhausted"
                    # else: soft hint already spoken for, fall through.

                if is_hard and candidate not in self.pool:
                    return None, None, "requested IP outside of pool"

                ip = self._get_pool_ip(mac, now)
                if ip:
                    already_held_by_self = (
                        (self.leases.get(ip) and self.leases[ip].mac == mac
                         and not self.leases[ip].is_expired())
                        or (self._reservations.get(ip, (None, 0))[0] == mac
                            and self._reservations.get(ip, (None, 0))[1] > now))
                    if not already_held_by_self:
                        bucket.append(now)
                    _grant(ip)
                    return ip, self.config.pool_def_lease, None

            return None, None, "pool exhausted"
        finally:
            if persist and snapshot_to_save is not None:
                self._save_snapshot(snapshot_to_save)

    def _get_pool_ip(self, mac, now=None):
        if now is None:
            now = time.time()

        existing = self.get_by_mac(mac)
        if existing and existing.ip in self.pool:
            return existing.ip

        for ip, (resv_mac, expiry) in self._reservations.items():
            if resv_mac == mac and expiry > now and ip in self.pool:
                return ip

        static_ips = set(self.config.static_hosts.values())
        active_ips = {ip for ip, lease in self.leases.items() if not lease.is_expired()}
        quarantined = {ip for ip, exp in self._quarantine.items() if exp > now}
        reserved = {ip for ip, (_, exp) in self._reservations.items() if exp > now}
        free = self.pool - active_ips - static_ips - quarantined - reserved
        if not free:
            return None
        sorted_free = sorted(free, key=self._ip_key)
        idx = self._alloc_counter % len(sorted_free)
        self._alloc_counter = (self._alloc_counter + 1) % (2**16)
        return sorted_free[idx]

    def _create_lease_locked(self, ip, mac, hostname, duration):
        # Caller must hold self.lock. Mutates self.leases and returns a
        # snapshot the caller is expected to persist after releasing the lock,
        # so disk I/O does not serialize concurrent allocations.
        now = time.time()
        lease = Lease(ip, mac, hostname, now, now + duration)
        self.leases[ip] = lease
        return dict(self.leases)

    def _create_lease(self, ip, mac, hostname, duration):
        with self.lock:
            snapshot = self._create_lease_locked(ip, mac, hostname, duration)
        self._save_snapshot(snapshot)

    def _save_snapshot(self, snapshot):
        if snapshot is None:
            return
        # Multiple worker threads can reach this point concurrently (allocate/
        # release/cleanup_expired/apply_config all persist outside self.lock
        # so disk I/O doesn't serialize allocations). _write_lock ensures only
        # one thread writes at a time, and re-reading self.leases fresh here
        # (instead of trusting the possibly-stale snapshot the caller captured
        # earlier) guarantees whichever write actually lands is never a
        # revert to older data.
        with self._write_lock:
            with self.lock:
                current = dict(self.leases)
            directory = os.path.dirname(self.path) or "."
            fd, tmp_path = tempfile.mkstemp(
                prefix=os.path.basename(self.path) + ".", dir=directory)
            try:
                with os.fdopen(fd, "w") as f:
                    for lease in current.values():
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
            except Exception:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                raise

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

    def release_owned(self, mac, ip):
        # Release a single lease only when it is currently held by this MAC.
        # Returns True if a lease was removed, False otherwise.
        mac = mac.lower()
        with self.lock:
            lease = self.leases.get(ip)
            if not lease or lease.mac != mac:
                return False
            del self.leases[ip]
            snapshot = dict(self.leases)
        self._save_snapshot(snapshot)
        return True

    def release_reservation_owned(self, mac, ip):
        # Drop a provisional (DISCOVER-only) hold immediately, e.g. when a
        # ping-check finds the IP already in use. Never touches disk —
        # reservations are in-memory only.
        mac = mac.lower()
        with self.lock:
            resv = self._reservations.get(ip)
            if resv and resv[0] == mac:
                del self._reservations[ip]
                return True
        return False

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
            stale_reservations = [ip for ip, (_, exp) in self._reservations.items() if exp <= now]
            for ip in stale_reservations:
                del self._reservations[ip]
            # Drop rate-limit buckets that have aged out completely so the map
            # does not grow unbounded for MACs that never come back (random-MAC
            # privacy on phones rotates the source MAC on every association).
            window_start = now - self._RATE_LIMIT_WINDOW
            stale_rate = []
            for key, bucket in self._rate.items():
                while bucket and bucket[0] < window_start:
                    bucket.popleft()
                if not bucket:
                    stale_rate.append(key)
            for key in stale_rate:
                del self._rate[key]
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
    pkt["hostname"] = re.sub(r'[\x00-\x1f\x7f"\\;{}%]', '', raw_hostname).strip()
    opt_req_ip = pkt["options"].get(OPT_REQUESTED_IP, b"\x00\x00\x00\x00")
    pkt["requested_ip"] = bytes_to_ip(opt_req_ip) if len(opt_req_ip) == 4 else "0.0.0.0"

    return pkt


def build_packet(msg_type, xid, mac_str, offered_ip, server_ip, config, lease_time,
                 broadcast=True, giaddr="0.0.0.0"):
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
    pkt[24:28] = ip_to_bytes(giaddr)
    pkt[28:34] = mac_bytes

    options = bytearray()
    options += DHCP_MAGIC

    def add_opt(code, value):
        nonlocal options
        if len(value) > 255:
            log.error("DHCP option %d value too long (%d bytes) — skipped",
                      code, len(value))
            return
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

    return _pad_to_min_bootp(bytes(pkt) + bytes(options))

# =============================================================================
# PING CHECK
# =============================================================================

_PING_CACHE_TTL = 120
_ping_cache_lock = threading.Lock()
_ping_cache = {}
_ping_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="ping")
# Caps how many DISCOVERs can have a ping-check outstanding at once. Without
# this, making ping-check non-blocking for the main pool (see _handle_discover)
# would just move the unbounded backlog from "blocked main-pool threads" to
# "an ever-growing queue inside _ping_executor" under a DISCOVER flood.
_PING_INFLIGHT_MAX = 64
_ping_inflight = threading.Semaphore(_PING_INFLIGHT_MAX)

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
                # Remove leases whose IP is no longer in the new pool so the
                # lease table stays consistent after a range change.
                stale = [ip for ip in list(self.leases.leases)
                         if ip not in new_pool
                         and ip not in new_config.static_hosts.values()]
                for ip in stale:
                    log.info("apply_config: removing lease %s (outside new pool)", ip)
                    del self.leases.leases[ip]
                stale_resv = [ip for ip in list(self.leases._reservations) if ip not in new_pool]
                for ip in stale_resv:
                    del self.leases._reservations[ip]
                snapshot = dict(self.leases.leases) if stale else None
            self.server_ip    = new_config.server_id or new_config.routers
            self.broadcast_ip = new_config.broadcast or BROADCAST_ADDR

        if snapshot is not None:
            self.leases._save_snapshot(snapshot)

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
        try:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE,
                                 self.interface.encode() + b"\0")
        except (OSError, AttributeError) as e:
            log.warning("Cannot bind UDP socket to interface %s (SO_BINDTODEVICE): %s "
                        "— replies rely on the kernel routing table", self.interface, e)
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
            src_ip  = bytes_to_ip(frame[ip_start + 12:ip_start + 16])

            if not self._inflight.acquire(blocking=False):
                self._dropped += 1
                if self._dropped % 100 == 1:
                    log.warning("Worker backlog full (%d) — dropping packets "
                                "(total dropped: %d)", self.MAX_INFLIGHT, self._dropped)
                continue
            try:
                self._thread_pool.submit(self._handle_packet, data, src_mac, src_ip)
            except RuntimeError:
                self._inflight.release()

    def _handle_packet(self, data, src_mac, src_ip):
        try:
            self._handle(data, src_mac, src_ip)
        except Exception as e:
            log.exception("Unhandled error in worker: %s", e)
        finally:
            self._inflight.release()

    def stop(self):
        self.running = False
        # Wait for in-flight worker tasks to finish before closing the
        # sockets they may still be using to send responses and persist
        # leases. This guarantees main()'s remove_pid() only runs once no
        # worker can still be writing to the leases file.
        self._thread_pool.shutdown(wait=True)
        if hasattr(self, 'raw_sock') and self.raw_sock:
            self.raw_sock.close()
        if self.sock:
            self.sock.close()
        log.info("pydhcpd stopped")

    def _cleanup_loop(self):
        while self.running:
            with self._config_lock:
                interval = self.config.cleanup_interval
            time.sleep(interval)
            self.leases.cleanup_expired()

    def _handle(self, data, src_mac, src_ip):
        pkt = parse_packet(data)
        if not pkt:
            return

        dhcp_giaddr = pkt.get("giaddr", "0.0.0.0")

        if dhcp_giaddr == "0.0.0.0":
            if pkt["chaddr"] != src_mac:
                log.warning("chaddr spoofing detected: frame src=%s chaddr=%s — dropped",
                            src_mac, pkt["chaddr"])
                return
        else:
            # Relayed traffic: a genuine relay agent increments hops and sources
            # the frame from giaddr itself. Reject anything else, so the server
            # cannot be steered into replying to an arbitrary giaddr (UDP
            # reflection) nor used to bypass the chaddr check above.
            if pkt.get("hops", 0) < 1 or dhcp_giaddr != src_ip:
                log.warning("Spoofed relay dropped: giaddr=%s frame src=%s hops=%d",
                            dhcp_giaddr, src_ip, pkt.get("hops", 0))
                return

        mac      = pkt["chaddr"]
        hostname = pkt["hostname"] or ""
        msg_type = pkt["msg_type"]
        log_hostname = hostname if hostname else "<no hostname>"

        if msg_type == MSG_DISCOVER:
            self._handle_discover(pkt, mac, hostname, log_hostname, src_mac)

        elif msg_type == MSG_REQUEST:
            self._handle_request(pkt, mac, hostname, log_hostname, src_mac)

        elif msg_type == MSG_DECLINE:
            with self._config_lock:
                config_deny_declines = self.config.deny_declines

            if config_deny_declines:
                log.warning("DECLINE from %s ignored (deny declines)", mac)
            else:
                # RFC 2131 4.4.5: the declined address travels in the
                # requested-ip option (falling back to ciaddr). Only act on it
                # when it is actually leased to this client, so a forged DECLINE
                # cannot quarantine an address belonging to someone else.
                declined_ip = pkt.get("requested_ip", "0.0.0.0")
                if declined_ip == "0.0.0.0":
                    declined_ip = pkt.get("ciaddr", "0.0.0.0")
                if self.leases.release_owned(mac, declined_ip):
                    self.leases.quarantine_ip(declined_ip)
                    log.info("DECLINE from %s: IP %s quarantined", mac, declined_ip)
                else:
                    log.warning("DECLINE from %s for %s not owned by it — ignored",
                                mac, declined_ip)

        elif msg_type == MSG_RELEASE:
            # RFC 2131 4.4.4: honour RELEASE only from the current lease holder.
            # ciaddr must carry the client's address and, when present, the
            # server-identifier must point at us. Prevents a forged RELEASE from
            # freeing another client's lease.
            ciaddr  = pkt.get("ciaddr", "0.0.0.0")
            sid_opt = pkt["options"].get(OPT_SERVER_ID, b"")
            if len(sid_opt) == 4 and bytes_to_ip(sid_opt) != self.server_ip:
                log.debug("RELEASE from %s targets another server — ignored", mac)
            elif ciaddr == "0.0.0.0":
                log.warning("RELEASE from %s without ciaddr — ignored", mac)
            elif self.leases.release_owned(mac, ciaddr):
                log.info("RELEASE from %s: %s", mac, ciaddr)
            else:
                log.warning("RELEASE from %s for %s not owned by it — ignored", mac, ciaddr)

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
        pkt_buf[16:20] = ip_to_bytes("0.0.0.0")
        pkt_buf[20:24] = ip_to_bytes(self.server_ip)
        pkt_buf[24:28] = ip_to_bytes(pkt.get("giaddr", "0.0.0.0"))
        pkt_buf[28:34] = mac_bytes

        options = bytearray()
        options += DHCP_MAGIC

        def add_opt(code, value):
            nonlocal options
            if len(value) > 255:
                log.error("DHCP option %d value too long (%d bytes) — skipped",
                          code, len(value))
                return
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

        reply = _pad_to_min_bootp(bytes(pkt_buf) + bytes(options))
        self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))

    def _handle_discover(self, pkt, mac, hostname, log_hostname, src_mac=None):
        log.info("DISCOVER from %s (%s)", mac, log_hostname)

        with self._config_lock:
            config_snapshot = self.config
            server_ip_snapshot = self.server_ip
            config_deny_duplicates = config_snapshot.deny_duplicates
            config_ping_check = config_snapshot.ping_check
            config_default_lease = config_snapshot.default_lease

        if config_deny_duplicates:
            existing = self.leases.get_by_mac(mac)
            if existing and not self.leases.is_blocked(mac):
                offered_ip  = existing.ip
                lease_time  = config_default_lease
                alloc_reason = None
            else:
                offered_ip, lease_time, alloc_reason = self.leases.allocate(
                    mac, hostname, hint_ip=pkt.get("requested_ip"), src_mac=src_mac,
                    persist=False, provisional=True)
        else:
            offered_ip, lease_time, alloc_reason = self.leases.allocate(
                mac, hostname, hint_ip=pkt.get("requested_ip"), src_mac=src_mac,
                persist=False, provisional=True)

        if not offered_ip:
            if alloc_reason and "blockdhcp" in alloc_reason:
                log.warning("Blocked: %s (deny blockdhcp)", mac)
            else:
                log.warning("No IP available for %s", mac)
            return

        is_static = bool(self.leases.get_static(mac))
        existing_lease = self.leases.get_by_mac(mac)
        is_own_ip = existing_lease and existing_lease.ip == offered_ip

        def _send_offer():
            xid_hex = pkt["xid"].hex()
            with self._pending_lock:
                self._pending[xid_hex] = offered_ip
                if len(self._pending) > 1024:
                    self._pending.popitem(last=False)

            use_broadcast = self._should_broadcast(pkt)
            reply = build_packet(MSG_OFFER, pkt["xid"], mac, offered_ip,
                                 server_ip_snapshot, config_snapshot, lease_time,
                                 broadcast=use_broadcast, giaddr=pkt.get("giaddr", "0.0.0.0"))
            if reply:
                self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))
                log.info("OFFER %s → %s", mac, offered_ip)

        if config_ping_check and not is_static and not is_own_ip:
            if _ping_inflight.acquire(blocking=False):
                def _on_ping_done(future):
                    try:
                        alive = future.result()
                    except Exception:
                        alive = False
                    finally:
                        _ping_inflight.release()
                    if alive:
                        log.warning("PING-CHECK: %s is in use — quarantined", offered_ip)
                        self.leases.quarantine_ip(offered_ip, duration=3600)
                        self.leases.release_reservation_owned(mac, offered_ip)
                        return
                    _send_offer()

                # Submit and return immediately: this frees the calling main-
                # pool worker right away instead of blocking it on the ping
                # for up to 2s. _on_ping_done runs on the ping executor's own
                # thread once the ping finishes, and does the send/quarantine.
                future = _ping_executor.submit(ping_check, offered_ip)
                future.add_done_callback(_on_ping_done)
                return
            else:
                # Ping subsystem saturated: fail open rather than blocking
                # (or dropping) the DISCOVER — an occasional missed conflict
                # check is far cheaper than starving the main pool.
                log.debug("Ping-check backlog full — sending OFFER for %s "
                          "without a conflict check", offered_ip)

        _send_offer()

    def _handle_request(self, pkt, mac, hostname, log_hostname, src_mac=None):
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

        if target_ip is None:
            # RFC 2131 §4.3.2: a REQUEST is only valid in SELECTING
            # (requested-ip set), INIT-REBOOT (requested-ip set) or
            # RENEWING/REBINDING (ciaddr set). One with neither and no
            # lease on record for this MAC is not a real client state —
            # honoring it would hand out a full, persisted lease with no
            # DISCOVER/ping-check and no proof of possession.
            log.debug("REQUEST from %s has no requested-ip/ciaddr and no "
                      "existing lease — dropped", mac)
            return

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
            # Drop the stale offer: the client will restart with a new xid.
            with self._pending_lock:
                self._pending.pop(xid_key, None)
            self._send_nak(pkt, mac, "Requested IP does not match offer")
            return

        with self._config_lock:
            config_snapshot = self.config
            server_ip_snapshot = self.server_ip
            config_auth = config_snapshot.authoritative
            config_one_per_client = config_snapshot.one_per_client
            config_pool_def_lease = config_snapshot.pool_def_lease

        if config_auth and target_ip:
            static_ip = self.leases.get_static(mac)
            if static_ip and target_ip != static_ip:
                log.info("NAK (authoritative) → %s requested %s but assigned %s",
                         mac, target_ip, static_ip)
                self._send_nak(pkt, mac, "Not authorized for this IP")
                return

        old_ip_to_release = None
        if config_one_per_client and target_ip:
            existing = self.leases.get_by_mac(mac)
            if existing and existing.ip != target_ip and not self.leases.is_blocked(mac):
                old_ip_to_release = existing.ip

        offered_ip, lease_time, alloc_reason = self.leases.allocate(mac, hostname, requested_ip=target_ip, src_mac=src_mac)

        if not offered_ip:
            self._send_nak(pkt, mac, alloc_reason or "No address available")
            return

        if old_ip_to_release and old_ip_to_release != offered_ip:
            # Only release the previous lease now that the new one is
            # confirmed, so a failed allocate() never leaves the client
            # with neither (was: release-then-allocate). This also keeps
            # release()'s disk fsync out of any lock allocate() needs for
            # other clients, instead of nesting it inside one long-held lock.
            self.leases.release_owned(mac, old_ip_to_release)

        with self._pending_lock:
            self._pending.pop(xid_key, None)

        use_broadcast = self._should_broadcast(pkt)
        reply = build_packet(MSG_ACK, pkt["xid"], mac, offered_ip,
                             server_ip_snapshot, config_snapshot, lease_time,
                             broadcast=use_broadcast, giaddr=pkt.get("giaddr", "0.0.0.0"))
        if reply:
            self._send(reply, giaddr=pkt.get("giaddr", "0.0.0.0"), ciaddr=pkt.get("ciaddr", "0.0.0.0"))
            log.info("ACK %s → %s (lease %ds)", mac, offered_ip, lease_time)

    def _send_nak(self, pkt, mac, reason=None):
        nak = bytearray(236)
        nak[0]   = 2
        nak[1]   = 1
        nak[2]   = 6
        nak[4:8] = pkt["xid"]
        nak[10:12] = struct.pack("!H", 0x8000)
        nak[24:28] = ip_to_bytes(pkt.get("giaddr", "0.0.0.0"))
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
        self._send(_pad_to_min_bootp(bytes(nak) + bytes(opts)),
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

def _pid_is_pydhcpd(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
    except OSError:
        return False
    return "pydhcpd.py" in cmdline

def write_pid(path):
    if os.path.exists(path):
        try:
            with open(path, 'r') as f:
                old_pid = int(f.read().strip())
        except (ValueError, OSError):
            old_pid = None
        if old_pid is not None:
            try:
                os.kill(old_pid, 0)
                alive = True
            except ProcessLookupError:
                alive = False
            except OSError:
                # Process exists but we cannot signal it (different owner).
                alive = True
            if alive and _pid_is_pydhcpd(old_pid):
                log.error("pydhcpd already running (pid %d) — refusing to start "
                          "a second instance", old_pid)
                sys.exit(1)
            elif alive:
                log.warning("PID %d in %s is alive but not pydhcpd — overwriting",
                            old_pid, path)
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
        # server-identifier is mandatory to start the daemon (checked in main());
        # validate it here too so -t does not report OK on a config that would
        # then fail at real startup.
        if not config.server_id:
            print("Configuration error: server-identifier not set")
            return False
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
        # Keep the handler minimal: flip the run flag and close the sockets so
        # the main loop unblocks and tears down cleanly via the finally clause.
        log.info("Signal %d received, shutting down...", signum)
        server.running = False
        server.stop()

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
