# pool_zones.py
# Converts raw GPS lat/lng readings into a named pool zone (e.g. "Deep End - Right")
# so lifeguards can identify a victim's location at a glance instead of reading
# raw coordinates.
#
# HOW TO CALIBRATE FOR YOUR REAL POOL:
# 1. Stand at one corner of the pool (e.g. the shallow-end left corner) and
#    note the GPS reading there — set that as POOL_ORIGIN_LAT / POOL_ORIGIN_LNG.
# 2. Measure your pool's actual length and width in meters — set POOL_LENGTH_M
#    and POOL_WIDTH_M accordingly.
# 3. Confirm POOL_ORIENTATION_DEG matches which compass direction the pool's
#    "length" axis (shallow-to-deep) points — 0 = pool length runs due North,
#    90 = pool length runs due East, etc. Adjust to match your pool's real
#    orientation.
#
# NOTE ON GPS ACCURACY: consumer GPS modules (like the SAM-M10Q) typically
# have 1-3m accuracy outdoors with a clear sky view. For a small pool, this
# means zone identification is approximate, not exact — treat it as "which
# general area" rather than a precise pinpoint. Accuracy also degrades
# significantly if the GPS antenna is underwater or has an obstructed sky
# view, which is worth testing in real conditions before relying on this.

import math

# ---------------------------------------------------------------------------
# PLACEHOLDER POOL CALIBRATION — replace with your real pool's measurements
# ---------------------------------------------------------------------------
POOL_ORIGIN_LAT = 30.2672   # GPS latitude at the shallow-end-left corner
POOL_ORIGIN_LNG = -97.7431  # GPS longitude at the shallow-end-left corner
POOL_LENGTH_M = 25.0        # distance from shallow end to deep end, in meters
POOL_WIDTH_M = 12.5         # distance from left side to right side, in meters
POOL_ORIENTATION_DEG = 0.0  # compass bearing of the "length" axis (shallow->deep)

# ---------------------------------------------------------------------------

EARTH_RADIUS_M = 6371000.0


def _latlng_to_local_meters(lat: float, lng: float) -> tuple[float, float]:
    """
    Converts a GPS lat/lng into local (x, y) meters relative to POOL_ORIGIN,
    using a flat-earth (equirectangular) approximation. This is accurate
    enough for small areas like a single pool (errors are negligible at
    this scale) but would not be appropriate for large-scale mapping.
    """
    lat_rad = math.radians(POOL_ORIGIN_LAT)

    dlat = lat - POOL_ORIGIN_LAT
    dlng = lng - POOL_ORIGIN_LNG

    y_m = dlat * (math.pi / 180) * EARTH_RADIUS_M
    x_m = dlng * (math.pi / 180) * EARTH_RADIUS_M * math.cos(lat_rad)

    # Rotate into the pool's own coordinate frame if it's not aligned to
    # true North/East
    if POOL_ORIENTATION_DEG != 0.0:
        theta = math.radians(POOL_ORIENTATION_DEG)
        x_rot = x_m * math.cos(theta) + y_m * math.sin(theta)
        y_rot = -x_m * math.sin(theta) + y_m * math.cos(theta)
        return x_rot, y_rot

    return x_m, y_m


def get_pool_position(lat: float | None, lng: float | None) -> dict:
    """
    Returns a structured dict describing where in the pool a reading falls:
      {
        "zone_number": int | None,      # 1-6, None if no fix / outside pool
        "depth_label": str,             # "Shallow Pool" / "Mid Pool" / "Deep Pool" / status text
        "side": str,                    # "Left" / "Right" / status text
        "zone_string": str,             # "Zone 3, Mid Pool, Left" (display-ready)
        "x_norm": float | None,         # 0.0-1.0 position across pool width, for plotting
        "y_norm": float | None,         # 0.0-1.0 position along pool length, for plotting
      }
    x_norm/y_norm are None when there's no GPS fix or the reading falls
    outside the calibrated pool rectangle — the caller should handle that
    (e.g. don't draw a marker) rather than plotting a misleading (0,0).
    """
    if lat is None or lng is None:
        return {
            "zone_number": None,
            "depth_label": "No GPS Fix",
            "side": "",
            "zone_string": "No GPS Fix",
            "x_norm": None,
            "y_norm": None,
        }

    x_m, y_m = _latlng_to_local_meters(lat, lng)

    if not (0 <= x_m <= POOL_WIDTH_M) or not (0 <= y_m <= POOL_LENGTH_M):
        return {
            "zone_number": None,
            "depth_label": "Outside Pool Area",
            "side": "",
            "zone_string": "Outside Pool Area",
            "x_norm": None,
            "y_norm": None,
        }

    side = "Left" if x_m < (POOL_WIDTH_M / 2) else "Right"
    side_index = 0 if side == "Left" else 1

    third = POOL_LENGTH_M / 3
    if y_m < third:
        depth_label = "Shallow Pool"
        depth_row = 0
    elif y_m < 2 * third:
        depth_label = "Mid Pool"
        depth_row = 1
    else:
        depth_label = "Deep Pool"
        depth_row = 2

    zone_number = (depth_row * 2) + side_index + 1

    return {
        "zone_number": zone_number,
        "depth_label": depth_label,
        "side": side,
        "zone_string": f"Zone {zone_number}, {depth_label}, {side}",
        "x_norm": x_m / POOL_WIDTH_M,
        "y_norm": y_m / POOL_LENGTH_M,
    }


def get_pool_zone(lat: float | None, lng: float | None) -> str:
    """Convenience wrapper — just the display string, for callers that don't
    need the full structured position data."""
    return get_pool_position(lat, lng)["zone_string"]
