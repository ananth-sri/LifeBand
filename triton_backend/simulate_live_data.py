# simulate_live_data.py
# Mimics the wearable's real edge-computing behavior: only transmits when
# a reading is CRITICAL or WARNING (computed via simple local thresholds,
# not the full server-side urgency score). Stable readings are never sent.
#
# Also generates a SIMULATED LoRa packet-loss-rate (plr) value per victim,
# with a slow random walk (and an occasional deliberate upward trend) so
# the dashboard's P1 "losing signal" priority logic has something real to
# demonstrate. This is NOT real packet-loss data - actual PLR tracking
# needs new gateway firmware (comparing expected vs. actually-received
# packet counts over a rolling window), which hasn't been built yet.
#
# Run this AFTER seed_data.py has registered the victims once.
# Leave it running in its own terminal tab - Ctrl+C to stop.

import json
import math
import random
import time
import urllib.request
import urllib.error
import os

BASE_URL = "http://localhost:8000"
API_KEY = os.environ.get("TRITON_API_KEY", "dev-key-change-me")
UPDATE_INTERVAL_SECONDS = 3
NUM_VICTIMS = 50
SOS_PROBABILITY = 0.02

SEARCH_AREA_ORIGIN_LAT = 26.5
SEARCH_AREA_ORIGIN_LNG = -90.5
SEARCH_AREA_LENGTH_M = 5000.0
SEARCH_AREA_WIDTH_M = 5000.0
EARTH_RADIUS_M = 6371000.0

# Per-victim simulated PLR state, so it can drift/trend over time instead
# of being a fresh random number every tick (a real signal degrading would
# trend, not jump around randomly).
_plr_state = {}


def classify_local(bpm, piezo_depth):
    if piezo_depth > 3500 or bpm > 140 or (bpm < 45 and bpm > 0):
        return "critical"
    if piezo_depth > 2200:
        return "warning"
    return "stable"


def simulate_plr(device_id):
    """SIMULATED ONLY - see module docstring. Slow random walk, with a
    small chance of a sustained upward trend (mimicking a device drifting
    out of range) to demonstrate the P1 priority feature."""
    state = _plr_state.setdefault(device_id, {"plr": random.uniform(0.0, 0.1), "trending": False})
    if not state["trending"] and random.random() < 0.03:
        state["trending"] = True
    if state["trending"]:
        state["plr"] = min(1.0, state["plr"] + random.uniform(0.02, 0.08))
        if state["plr"] >= 0.9 or random.random() < 0.05:
            state["trending"] = False
            state["plr"] = random.uniform(0.0, 0.1)
    else:
        state["plr"] = max(0.0, min(0.3, state["plr"] + random.uniform(-0.02, 0.02)))
    return round(state["plr"], 3)


def meters_to_latlng(x_m, y_m):
    lat_rad = math.radians(SEARCH_AREA_ORIGIN_LAT)
    dlat = y_m / (EARTH_RADIUS_M * (math.pi / 180))
    dlng = x_m / (EARTH_RADIUS_M * math.cos(lat_rad) * (math.pi / 180))
    return SEARCH_AREA_ORIGIN_LAT + dlat, SEARCH_AREA_ORIGIN_LNG + dlng


def post_telemetry(device_id, bpm, piezo_depth, sos, plr):
    x_m = random.uniform(0, SEARCH_AREA_WIDTH_M)
    y_m = random.uniform(0, SEARCH_AREA_LENGTH_M)
    lat, lng = meters_to_latlng(x_m, y_m)
    battery_pct = random.uniform(15, 100)

    payload = {
        "device_id": device_id,
        "bpm": round(bpm, 1),
        "piezo_depth": piezo_depth,
        "latitude": round(lat, 6),
        "longitude": round(lng, 6),
        "battery_pct": round(battery_pct, 1),
        "sos": sos,
        "plr": plr,
    }

    url = f"{BASE_URL}/telemetry"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "X-API-Key": API_KEY},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
        return True
    except urllib.error.HTTPError as e:
        print(f"  ERROR {e.code} for {device_id}: {e.read().decode('utf-8')}")
        return False
    except urllib.error.URLError as e:
        print(f"  Connection error: {e}")
        return False


def main():
    print(f"Simulating EDGE-COMPUTING wearables for {NUM_VICTIMS} victims in open Gulf waters.")
    print("Only transmits when a reading is CRITICAL or WARNING.")
    print("PLR values are SIMULATED (no real gateway packet-loss tracking exists yet).\n")
    print("Leave this running - Ctrl+C to stop.\n")

    tick = 0
    while True:
        tick += 1
        transmitted = []
        skipped_stable = 0

        for i in range(1, NUM_VICTIMS + 1):
            device_id = f"LB{i:03d}"

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

            classification = classify_local(bpm, piezo_depth)
            plr = simulate_plr(device_id)

            if classification == "stable":
                skipped_stable += 1
                continue

            sos = random.random() < SOS_PROBABILITY
            if post_telemetry(device_id, bpm, piezo_depth, sos, plr):
                transmitted.append(f"{device_id}:{classification}{'[SOS]' if sos else ''}[plr={plr}]")

        msg = f"Tick {tick}: {len(transmitted)} transmitted, {skipped_stable} stayed silent (stable)"
        if transmitted:
            msg += f"\n  -> {', '.join(transmitted)}"
        print(msg)
        time.sleep(UPDATE_INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")