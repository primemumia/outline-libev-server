#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""UDP client for shadowsocks-libev ss-manager."""

import json
import socket
from typing import Any, Dict, Optional


class LibevManagerClient:
    def __init__(self, manager_address: str, timeout: float = 5.0):
        self.manager_address = manager_address
        self.timeout = timeout
        self._host, self._port = self._parse_address(manager_address)

    @staticmethod
    def _parse_address(address: str):
        if address.startswith("/"):
            return address, None
        if ":" in address:
            host, port = address.rsplit(":", 1)
            return host, int(port)
        return address, 6001

    def _send(self, command: str) -> str:
        if self._port is None:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            target = self._host
        else:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            target = (self._host, self._port)

        sock.settimeout(self.timeout)
        try:
            sock.sendto(command.encode("utf-8"), target)
            data, _ = sock.recvfrom(65535)
            return data.decode("utf-8", errors="replace").strip("\x00")
        finally:
            sock.close()

    def add_port(self, port: int, password: str, method: str = "chacha20-ietf-poly1305") -> None:
        payload = {
            "server_port": port,
            "password": password,
            "method": method,
        }
        resp = self._send(f"add {json.dumps(payload, separators=(',', ':'))}")
        if resp != "ok":
            raise RuntimeError(resp or "add failed")

    def remove_port(self, port: int) -> None:
        payload = {"server_port": port}
        resp = self._send(f"remove {json.dumps(payload, separators=(',', ':'))}")
        if resp != "ok":
            raise RuntimeError(resp or "remove failed")

    def list_ports(self) -> list:
        resp = self._send("list")
        if not resp:
            return []
        return json.loads(resp)

    def ping(self) -> Dict[str, Any]:
        resp = self._send("ping")
        if resp.startswith("stat:"):
            resp = resp.split(":", 1)[1].strip()
        return json.loads(resp or "{}")

    def set_ip(self, port: int, ip: str) -> None:
        payload = {"server_port": port, "ip": ip}
        resp = self._send(f"set_ip {json.dumps(payload, separators=(',', ':'))}")
        if resp != "ok":
            raise RuntimeError(resp or "set_ip failed")

    def clear_ip(self, port: int) -> None:
        payload = {"server_port": port}
        resp = self._send(f"clear_ip {json.dumps(payload, separators=(',', ':'))}")
        if resp != "ok":
            raise RuntimeError(resp or "clear_ip failed")

    def ip_status(self, port: int) -> Dict[str, Any]:
        payload = {"server_port": port}
        resp = self._send(f"ip_status {json.dumps(payload, separators=(',', ':'))}")
        return json.loads(resp or "{}")
