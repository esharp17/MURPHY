"""robot_ui.location_service

QObject that provides the laptop's geolocation and local temperature
to QML as properties.

Location sources (in priority order):
  1. Windows native  – Windows.Devices.Geolocation (Wi-Fi / GPS, ~10-50 m)
  2. IP geolocation  – http://ip-api.com/json  (~1-10 km fallback)

Weather source (free, no key):
  - https://api.open-meteo.com/v1/forecast
"""

from __future__ import annotations

import json
import ssl
import subprocess
import sys
import threading
import urllib.request
from PySide6.QtCore import QObject, Signal, Slot, Property


# ── helpers ──────────────────────────────────────────────────────────

def _url_open(url, timeout=10):
    """urlopen with SSL fallback for machines with cert issues."""
    req = urllib.request.Request(url, headers={"User-Agent": "MurphyApp/1.0"})
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except (ssl.SSLError, ssl.SSLCertVerificationError, urllib.error.URLError):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        print("[LocationService] SSL fallback — retrying without cert verification", flush=True)
        return urllib.request.urlopen(req, timeout=timeout, context=ctx)


# PowerShell script that uses Windows.Devices.Geolocation WinRT API.
# Key points:
#   - DesiredAccuracyInMeters = 1  → requests the highest precision the OS can give
#   - We wait up to 30 s for the async result so the OS has time to get a real fix
#   - Returns JSON with lat, lon, accuracy (metres), and source hint
_WIN_GEO_PS = r"""
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Load the WinRT Geolocator type
[Windows.Devices.Geolocation.Geolocator, Windows.Devices.Geolocation, ContentType = WindowsRuntime] | Out-Null

$geo = New-Object Windows.Devices.Geolocation.Geolocator
$geo.DesiredAccuracyInMeters = 1

# Request position (async → Task)
$asyncOp  = $geo.GetGeopositionAsync()
$taskType = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } |
            Select-Object -First 1
$closedMethod = $taskType.MakeGenericMethod([Windows.Devices.Geolocation.Geoposition])
$task = $closedMethod.Invoke($null, @($asyncOp))

# Wait up to 30 seconds for a fix
if (-not $task.Wait(30000)) {
    throw 'Geolocation timed out after 30 s'
}
$pos = $task.Result

[pscustomobject]@{
    lat      = $pos.Coordinate.Point.Position.Latitude
    lon      = $pos.Coordinate.Point.Position.Longitude
    accuracy = $pos.Coordinate.Accuracy
    source   = $pos.Coordinate.PositionSource.ToString()
} | ConvertTo-Json -Compress
""".strip()


class LocationService(QObject):
    """Singleton exposed to QML as ``LocationService``."""

    locationChanged = Signal()

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)
        self._lat: float = 0.0
        self._lon: float = 0.0
        self._temp_f: float = 0.0
        self._temp_c: float = 0.0
        self._coords_str: str = "Fetching..."
        self._temp_str: str = "..."
        self._source: str = ""
        self._ready: bool = False

        # Fetch on startup in a background thread
        threading.Thread(target=self._fetch_all, daemon=True).start()

    # ------------------------------------------------------------------
    # Properties for QML
    # ------------------------------------------------------------------

    @Property(str, notify=locationChanged)
    def coords(self) -> str:
        return self._coords_str

    @Property(str, notify=locationChanged)
    def temperature(self) -> str:
        return self._temp_str

    @Property(float, notify=locationChanged)
    def lat(self) -> float:
        return self._lat

    @Property(float, notify=locationChanged)
    def lon(self) -> float:
        return self._lon

    @Property(float, notify=locationChanged)
    def tempF(self) -> float:
        return self._temp_f

    @Property(float, notify=locationChanged)
    def tempC(self) -> float:
        return self._temp_c

    @Property(bool, notify=locationChanged)
    def ready(self) -> bool:
        return self._ready

    @Property(str, notify=locationChanged)
    def source(self) -> str:
        return self._source

    # ------------------------------------------------------------------
    # QML-callable refresh
    # ------------------------------------------------------------------

    @Slot()
    def refresh(self):
        """Re-fetch location and temperature."""
        threading.Thread(target=self._fetch_all, daemon=True).start()

    # ------------------------------------------------------------------
    # Background fetchers
    # ------------------------------------------------------------------

    def _fetch_all(self):
        ok = True

        # ── location ──
        try:
            self._fetch_location()
        except Exception as e:
            print(f"[LocationService] location fetch FAILED: {type(e).__name__}: {e}", flush=True)
            self._coords_str = "Unavailable"
            self._source = "none"
            ok = False

        # ── weather ──
        try:
            if self._lat != 0.0 or self._lon != 0.0:
                self._fetch_weather()
            else:
                self._temp_str = "N/A"
        except Exception as e:
            print(f"[LocationService] weather fetch FAILED: {type(e).__name__}: {e}", flush=True)
            self._temp_str = "N/A"
            ok = False

        self._ready = True
        self.locationChanged.emit()

        if not ok:
            print("[LocationService] will retry in 30 seconds...", flush=True)
            t = threading.Timer(30.0, self._fetch_all)
            t.daemon = True
            t.start()

    # ── location strategies ──────────────────────────────────────────

    def _fetch_location(self):
        """Try Windows native first, then fall back to IP geolocation."""
        print("[LocationService] fetching location...", flush=True)

        if sys.platform == "win32":
            try:
                self._fetch_location_windows()
                return
            except Exception as ex:
                print(f"[LocationService] Windows native FAILED: "
                      f"{type(ex).__name__}: {ex}", flush=True)
                print("[LocationService] falling back to IP geolocation...", flush=True)

        self._fetch_location_ip()

    def _fetch_location_windows(self):
        """Windows native geolocation via PowerShell WinRT (high accuracy)."""
        import tempfile, os
        print("[LocationService] trying Windows native geolocation...", flush=True)

        # Write PS script to a temp file to avoid $ being stripped by subprocess
        fd, ps_path = tempfile.mkstemp(suffix=".ps1", prefix="murphy_geo_")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(_WIN_GEO_PS)

            cmd = [
                "powershell", "-NoProfile", "-NonInteractive",
                "-ExecutionPolicy", "Bypass", "-File", ps_path,
            ]
            cp = subprocess.run(
                cmd, capture_output=True, text=True,
                timeout=45,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        finally:
            try:
                os.unlink(ps_path)
            except OSError:
                pass

        if cp.returncode != 0:
            err = (cp.stderr or cp.stdout or "").strip()
            raise RuntimeError(err or f"exit code {cp.returncode}")

        raw = (cp.stdout or "").strip()
        print(f"[LocationService] Windows response: {raw[:300]}", flush=True)
        data = json.loads(raw)

        self._lat = float(data["lat"])
        self._lon = float(data["lon"])
        acc = float(data.get("accuracy", 0))
        src = data.get("source", "Windows")

        self._source = f"Windows ({src})"
        self._coords_str = f"{self._lat:.6f}, {self._lon:.6f}  (±{acc:.0f}m)"
        print(f"[LocationService] ✓ Windows native: {self._coords_str}  "
              f"[source={src}]", flush=True)

    def _fetch_location_ip(self):
        """Fallback: IP geolocation via ip-api.com (~city-level)."""
        print("[LocationService] trying IP geolocation...", flush=True)
        with _url_open("http://ip-api.com/json/?fields=lat,lon,city,regionName") as resp:
            raw = resp.read().decode()
            print(f"[LocationService] IP response: {raw[:200]}", flush=True)
            data = json.loads(raw)

        self._lat = float(data.get("lat", 0))
        self._lon = float(data.get("lon", 0))
        city = data.get("city", "")
        region = data.get("regionName", "")

        self._source = "IP"
        self._coords_str = f"{self._lat:.4f}, {self._lon:.4f}"
        if city:
            self._coords_str += f"  ({city}, {region})"
        print(f"[LocationService] ✓ IP fallback: {self._coords_str}", flush=True)

    # ── weather ──────────────────────────────────────────────────────

    def _fetch_weather(self):
        """Current temperature from Open-Meteo (free, no key)."""
        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={self._lat}&longitude={self._lon}"
            f"&current_weather=true&temperature_unit=fahrenheit"
        )
        print(f"[LocationService] fetching weather for "
              f"{self._lat:.4f},{self._lon:.4f}...", flush=True)
        with _url_open(url) as resp:
            raw = resp.read().decode()
            data = json.loads(raw)
        weather = data.get("current_weather", {})
        self._temp_f = float(weather.get("temperature", 0))
        self._temp_c = round((self._temp_f - 32) * 5 / 9, 1)
        self._temp_str = f"{self._temp_f:.0f}°F / {self._temp_c:.0f}°C"
        print(f"[LocationService] ✓ temperature: {self._temp_str}", flush=True)
