# triage.py
# All triage/urgency calculation logic lives here, separated from the API
# routing code so it can be reviewed, tested, and recalibrated independently.
#
# ============================================================================
# IMPORTANT — READ BEFORE DEPLOYING ANYWHERE NEAR REAL USE
# ============================================================================
# This is a first-draft scoring model, not a clinically validated one. Every
# threshold and weight below is a reasonable-sounding placeholder based on
# general exercise-physiology/first-aid heuristics — NOT sourced from a
# medical review or validated against real drowning/flood incident data.
# Before this drives any real safety decision, it needs review by someone
# with actual clinical/EMS triage expertise. Flagged inline wherever a number
# was picked as a placeholder rather than derived from a cited source.
# ============================================================================

import math
from typing import Optional

# ---------------------------------------------------------------------------
# CALIBRATION CONSTANTS — placeholders, adjust to your real hardware/scenario
# ---------------------------------------------------------------------------

# Piezo sensor raw reading (0-4095, from the ESP32's ADC) mapped to a real
# depth in meters. PLACEHOLDER — calibrate this against your actual piezo
# disc's real-world response curve once you have it submerged at known depths.
PIEZO_MAX_DEPTH_M = 3.0

# Depth at which a victim is considered fully critical (e.g., fully submerged
# past recovery window). PLACEHOLDER — set based on your actual pool depth
# and response time assumptions.
CRITICAL_DEPTH_M = 2.0

# Bradycardia floor — BPM below this is dangerously low regardless of age.
# Flat value here; a more accurate model would adjust this for age too
# (infants/elderly have different low-end norms), left flat for now.
BRADYCARDIA_FLOOR_BPM = 50.0

# Fraction of Tanaka-derived max HR considered the "danger zone" onset.
# 85% is a commonly-used heuristic in exercise physiology for high-intensity
# zones — borrowed here as a placeholder, not a clinical drowning-specific
# threshold.
DANGER_HR_FRACTION = 0.85

# Reference point for distance calculation (e.g., lifeguard station / shore
# access point). PLACEHOLDER — currently reuses the pool origin coordinate;
# update to your actual rescue-response reference point.
REFERENCE_LAT = 30.2672
REFERENCE_LNG = -97.7431

# Battery drain rate (% per minute) considered critical — i.e., the device
# might die soon, losing its ability to alert. PLACEHOLDER.
DRAIN_CRITICAL_PCT_PER_MIN = 2.0

# Default age used if a victim's age wasn't provided at registration.
# PLACEHOLDER fallback only — always provide a real age when registering
# a victim if at all possible, since age drives several thresholds below.
DEFAULT_AGE_YEARS = 30

# Urgency score component weights — MUST sum to 1.0. Tunable, not validated.
WEIGHT_HR = 0.40          # heart rate deviation / shock-index proxy
WEIGHT_DEPTH = 0.35       # rising water / time-to-critical-depth
WEIGHT_AGE = 0.15         # age-based vulnerability
WEIGHT_BATTERY = 0.10     # device battery reliability risk


# ---------------------------------------------------------------------------
# Age-adjusted heart rate thresholds (Tanaka formula)
# ---------------------------------------------------------------------------

def compute_bpm_critical(age_years: Optional[float]) -> float:
    """
    Tanaka formula for age-predicted maximum heart rate:
        HRmax = 208 - (0.7 x age)
    Used here as the 'critical' BPM ceiling for a given victim's age.
    """
    age = age_years if age_years is not None else DEFAULT_AGE_YEARS
    return 208.0 - (0.7 * age)


def compute_bpm_norm_high(age_years: Optional[float]) -> float:
    """Danger-zone onset — DANGER_HR_FRACTION of the Tanaka max HR."""
    return DANGER_HR_FRACTION * compute_bpm_critical(age_years)


def compute_bpm_norm_low(age_years: Optional[float]) -> float:
    """Bradycardia floor. Flat for now — see BRADYCARDIA_FLOOR_BPM comment."""
    return BRADYCARDIA_FLOOR_BPM


def compute_age_vulnerability(age_years: Optional[float]) -> float:
    """
    Simple U-shaped vulnerability score (0-1): very young and elderly victims
    are more physiologically vulnerable in a drowning/flood scenario than
    healthy young adults. PLACEHOLDER piecewise bands, not derived from a
    specific study — a real version of this should probably be a smooth
    curve fit to actual incident/outcome data.
    """
    age = age_years if age_years is not None else DEFAULT_AGE_YEARS
    if age < 12 or age > 65:
        return 1.0
    elif age < 18 or age > 50:
        return 0.6
    else:
        return 0.3


# ---------------------------------------------------------------------------
# Depth / rise-rate
# ---------------------------------------------------------------------------

def compute_depth_m(piezo_depth_raw: int) -> float:
    """Converts the raw 0-4095 piezo ADC reading into meters."""
    return (piezo_depth_raw / 4095.0) * PIEZO_MAX_DEPTH_M


def compute_rise_rate_m_per_hr(
    current_depth_m: float,
    previous_depth_m: Optional[float],
    hours_elapsed: Optional[float],
) -> Optional[float]:
    """
    Rate of change in depth, in meters/hour. Returns None if there's no
    previous reading to compare against (e.g. this is the victim's first
    reading) or if the time elapsed is effectively zero (avoids divide-by-zero
    from duplicate/near-simultaneous timestamps).
    """
    if previous_depth_m is None or hours_elapsed is None or hours_elapsed <= 0:
        return None
    return (current_depth_m - previous_depth_m) / hours_elapsed


def compute_hours_to_critical_depth(
    current_depth_m: float, rise_rate_m_per_hr: Optional[float]
) -> Optional[float]:
    """
    Estimated hours until the victim reaches CRITICAL_DEPTH_M, given the
    current rise rate. Returns:
      - 0.0 if already at/past critical depth
      - None if not currently rising (rate <= 0, or no rate available) —
        i.e. not on a worsening trajectory right now
    """
    if current_depth_m >= CRITICAL_DEPTH_M:
        return 0.0
    if rise_rate_m_per_hr is None or rise_rate_m_per_hr <= 0:
        return None
    return (CRITICAL_DEPTH_M - current_depth_m) / rise_rate_m_per_hr


# ---------------------------------------------------------------------------
# Battery
# ---------------------------------------------------------------------------

def compute_battery_drain_pct_per_min(
    current_battery_pct: Optional[float],
    previous_battery_pct: Optional[float],
    minutes_elapsed: Optional[float],
) -> Optional[float]:
    """Battery drain rate (%/min). None if we don't have two data points yet."""
    if (
        current_battery_pct is None
        or previous_battery_pct is None
        or minutes_elapsed is None
        or minutes_elapsed <= 0
    ):
        return None
    return (previous_battery_pct - current_battery_pct) / minutes_elapsed


# ---------------------------------------------------------------------------
# Distance
# ---------------------------------------------------------------------------

def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Standard haversine great-circle distance, in kilometers."""
    R = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * R * math.asin(math.sqrt(a))


def compute_dist_km(lat: Optional[float], lng: Optional[float]) -> Optional[float]:
    if lat is None or lng is None:
        return None
    return haversine_km(REFERENCE_LAT, REFERENCE_LNG, lat, lng)


# ---------------------------------------------------------------------------
# Urgency score — the combined, weighted 0-100 triage priority number
# ---------------------------------------------------------------------------

def compute_urgency(
    bpm: float,
    bpm_norm_low: float,
    bpm_norm_high: float,
    bpm_critical: float,
    hours_to_critical_depth: Optional[float],
    age_vulnerability: float,
    battery_drain_pct_per_min: Optional[float],
) -> tuple[float, bool]:
    """
    Returns (urgency_score 0-100, covered_urgency_stop).

    covered_urgency_stop: True once the RAW (pre-clamp) weighted score would
    already exceed the maximum (i.e. multiple risk factors are independently
    severe enough that the victim is already at max priority — further
    escalation isn't meaningful, this is a ceiling-hit flag). NOTE: this is
    my interpretation of what "covered_urgency_stop" should mean — flag if
    you intended something different, since the name wasn't otherwise defined.

    --- HR risk component ---
    NOTE ON SHOCK INDEX: true Shock Index = HR / systolic BP, which we can't
    compute without a blood pressure sensor. The line below is a PROXY —
    current BPM relative to this victim's age-adjusted critical BPM — folded
    into the HR risk component. It is NOT a real Shock Index and should never
    be surfaced to a user under that name, since it isn't actually measuring
    the same clinical thing.
    """
    # HR risk: how far outside the normal band, plus the shock-index-style
    # proxy, whichever is higher.
    if bpm < bpm_norm_low or bpm > bpm_norm_high:
        band_width = max(bpm_norm_high - bpm_norm_low, 1.0)
        deviation = max(bpm_norm_low - bpm, bpm - bpm_norm_high, 0.0)
        hr_deviation_risk = min(deviation / band_width, 1.0)
    else:
        hr_deviation_risk = 0.0

    shock_proxy = bpm / bpm_critical if bpm_critical > 0 else 0.0
    hr_risk = max(hr_deviation_risk, min(shock_proxy, 1.5) / 1.5)

    # Depth risk: inverse of hours-to-critical (sooner = higher risk).
    # If not currently rising, this component contributes no risk.
    if hours_to_critical_depth is None:
        depth_risk = 0.0
    elif hours_to_critical_depth <= 0:
        depth_risk = 1.0
    else:
        # Risk ramps up as hours-to-critical shrinks toward 0; treat
        # anything beyond a 2-hour horizon as low urgency from this factor.
        depth_risk = max(0.0, min(1.0, 1.0 - (hours_to_critical_depth / 2.0)))

    # Battery risk
    if battery_drain_pct_per_min is None:
        battery_risk = 0.0
    else:
        battery_risk = max(0.0, min(1.0, battery_drain_pct_per_min / DRAIN_CRITICAL_PCT_PER_MIN))

    raw_score = (
        WEIGHT_HR * hr_risk
        + WEIGHT_DEPTH * depth_risk
        + WEIGHT_AGE * age_vulnerability
        + WEIGHT_BATTERY * battery_risk
    )

    covered_urgency_stop = raw_score >= 1.0
    urgency_score = round(min(raw_score, 1.0) * 100, 1)

    return urgency_score, covered_urgency_stop
