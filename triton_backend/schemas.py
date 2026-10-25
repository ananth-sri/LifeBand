# schemas.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List


class TelemetryCreate(BaseModel):
    device_id: str
    bpm: float
    piezo_depth: int
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    battery_pct: Optional[float] = None
    sos: Optional[bool] = False
    plr: Optional[float] = None  # LoRa packet loss rate, 0.0-1.0


class TelemetryOut(BaseModel):
    id: int
    victim_id: int
    timestamp: datetime
    latitude: Optional[float]
    longitude: Optional[float]
    bpm: float
    piezo_depth: int

    depth_m: float
    rise_rate_m_per_hr: Optional[float]
    bpm_critical: float
    hours_to_critical_depth: Optional[float]
    urgency_score: float
    covered_urgency_stop: bool
    dist_km: Optional[float]
    age_years: Optional[float]
    bpm_norm_low: float
    bpm_norm_high: float
    age_vulnerability: float
    battery_pct: Optional[float]
    battery_drain_pct_per_min: Optional[float]
    sos: bool
    plr: Optional[float]

    zone_number: Optional[int]
    pool_zone: str
    pool_x_norm: Optional[float]
    pool_y_norm: Optional[float]

    class Config:
        from_attributes = True


class VictimOut(BaseModel):
    id: int
    name: str
    device_id: str
    age_years: Optional[float]
    acknowledged: bool
    acknowledged_at: Optional[datetime]
    latest_telemetry: Optional[TelemetryOut] = None

    class Config:
        from_attributes = True


class VictimCreate(BaseModel):
    name: str
    device_id: str
    age_years: Optional[float] = None
    id: Optional[int] = None