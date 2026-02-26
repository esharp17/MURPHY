"""robot_ui.location_service

QObject that provides the laptop's geolocation (via IP) and local
temperature (via Open-Meteo) to QML as properties.

No API keys required — uses:
  - http://ip-api.com/json  (IP geolocation)
  - https://api.open-meteo.com/v1/forecast  (weather)
"""

from __future__ import annotations

import json
import ssl
import threading
import urllib.request
from PySide6.QtCore import QObject, Signal, Slot, Property, QTimer


def _url_open(url, timeout=10):
    """urlopen with SSL fallback for machines with cert issues."""
    req = urllib.request.Request(url, headers={"User-Agent": "MurphyApp/1.0"})
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except (ssl.SSLError, ssl.SSLCertVerificationError, urllib.error.URLError):
        # Retry without SSL verification (common on locked-down machines)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        print("[LocationService] SSL fallback — retrying without cert verification", flush=True)
        return urllib.request.urlopen(req, timeout=timeout, context=ctx)


class LocationService(QObject):
    """Singleton exposed to QML as LocationService."""

    locationChanged = Signal()

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)
        self._lat: float = 0.0
        self._lon: float = 0.0
        self._temp_f: float = 0.0
        self._temp_c: float = 0.0
        self._coords_str: str = "Fetching..."
        self._temp_str: str = "..."
        self._ready: bool = False

        # Fetch on startup in a background thread
        self._fetch_thread = threading.Thread(target=self._fetch_all, daemon=True)
        self._fetch_thread.start()

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

    # ------------------------------------------------------------------
    # QML-callable refresh
    # ------------------------------------------------------------------

    @Slot()
    def refresh(self):
        """Re-fetch location and temperature."""
        t = threading.Thread(target=self._fetch_all, daemon=True)
        t.start()

    # ------------------------------------------------------------------
    # Background fetchers
    # ------------------------------------------------------------------

    def _fetch_all(self):
        ok = True
        try:
            self._fetch_location()
        except Exception as e:
            print(f"[LocationService] location fetch FAILED: {type(e).__name__}: {e}", flush=True)
            self._coords_str = "Unavailable (no network?)"
            ok = False

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

        # Auto-retry every 30s if either fetch failed
        if not ok:
            print("[LocationService] will retry in 30 seconds...", flush=True)
            t = threading.Timer(30.0, self._fetch_all)
            t.daemon = True
            t.start()

    def _fetch_location(self):
        """Get lat/lon from IP geolocation (ip-api.com)."""
        print("[LocationService] fetching location...", flush=True)
        with _url_open("http://ip-api.com/json/?fields=lat,lon,city,regionName") as resp:
            raw = resp.read().decode()
            print(f"[LocationService] location response: {raw[:200]}", flush=True)
            data = json.loads(raw)
        self._lat = float(data.get("lat", 0))
        self._lon = float(data.get("lon", 0))
        city = data.get("city", "")
        region = data.get("regionName", "")
        self._coords_str = f"{self._lat:.4f}, {self._lon:.4f}"
        if city:
            self._coords_str += f"  ({city}, {region})"
        print(f"[LocationService] location: {self._coords_str}", flush=True)

    def _fetch_weather(self):
        """Get current temperature from Open-Meteo (free, no key)."""
        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={self._lat}&longitude={self._lon}"
            f"&current_weather=true&temperature_unit=fahrenheit"
        )
        print(f"[LocationService] fetching weather for {self._lat},{self._lon}...", flush=True)
        with _url_open(url) as resp:
            raw = resp.read().decode()
            print(f"[LocationService] weather response: {raw[:200]}", flush=True)
            data = json.loads(raw)
        weather = data.get("current_weather", {})
        self._temp_f = float(weather.get("temperature", 0))
        self._temp_c = round((self._temp_f - 32) * 5 / 9, 1)
        self._temp_str = f"{self._temp_f:.0f}°F / {self._temp_c:.0f}°C"
        print(f"[LocationService] temperature: {self._temp_str}", flush=True)
