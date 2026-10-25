# seed_data.py
# Populates the database with 50 test swimmers (LB001-LB050) via the live
# API - not direct DB inserts.
#
# Usage (with the backend already running in another terminal):
#   source venv/bin/activate
#   python3 seed_data.py

import json
import math
import random
import urllib.request
import urllib.error
import os

BASE_URL = "http://localhost:8000"

# Must match your backend's TRITON_API_KEY env var (or the "dev-key-change-me"
# default if you haven't set one).
API_KEY = os.environ.get("TRITON_API_KEY", "dev-key-change-me")

POOL_ORIGIN_LAT = 30.2672
POOL_ORIGIN_LNG = -97.7431
POOL_LENGTH_M = 25.0
POOL_WIDTH_M = 12.5
EARTH_RADIUS_M = 6371000.0


def meters_to_latlng(x_m: float, y_m: float) -> tuple[float, float]:
    lat_rad = math.radians(POOL_ORIGIN_LAT)
    dlat = y_m / (EARTH_RADIUS_M * (math.pi / 180))
    dlng = x_m / (EARTH_RADIUS_M * math.cos(lat_rad) * (math.pi / 180))
    return POOL_ORIGIN_LAT + dlat, POOL_ORIGIN_LNG + dlng


def post_json(path: str, payload: dict) -> dict:
    url = f"{BASE_URL}{path}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "X-API-Key": API_KEY},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"  ERROR {e.code} on {path}: {e.read().decode('utf-8')}")
        return {}


def main():
    print(f"Seeding 50 swimmers into {BASE_URL} ...")

    for i in range(1, 51):
        band_id = f"LB{i:03d}"
        age = random.randint(6, 75)

        victim = post_json("/victims", {
            "id": i,
            "name": band_id,
            "device_id": band_id,
            "age_years": age,
        })
        if not victim:
            print(f"  Skipping telemetry for {band_id} (registration failed - may already exist)")
            continue

        x_m = random.uniform(0, POOL_WIDTH_M)
        y_m = random.uniform(0, POOL_LENGTH_M)
        lat, lng = meters_to_latlng(x_m, y_m)

        roll = random.random()
        if roll < 0.10:
            bpm = random.choice([random.uniform(145, 170), random.uniform(30, 40)])
            piezo_depth = random.randint(3600, 4095)
        elif roll < 0.25:
            bpm = random.uniform(100, 140)
            piezo_depth = random.randint(2300, 3400)
        else:
            bpm = random.uniform(65, 95)
            piezo_depth = random.randint(700, 2000)

        battery_pct = random.uniform(15, 100)

        post_json("/telemetry", {
            "device_id": band_id,
            "bpm": round(bpm, 1),
            "piezo_depth": piezo_depth,
            "latitude": round(lat, 6),
            "longitude": round(lng, 6),
            "battery_pct": round(battery_pct, 1),
        })

        print(f"  {band_id}  age={age}  bpm={bpm:.0f}  depth_raw={piezo_depth}  battery={battery_pct:.0f}%")

    print("Done. Open the dashboard at http://localhost:8000/dashboard")


if __name__ == "__main__":
    main()
