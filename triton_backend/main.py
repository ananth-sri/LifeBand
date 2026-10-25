# main.py
# Triton Lifeband backend API.
#
# Run locally with: ./start_backend.sh
# Interactive API docs: http://localhost:8000/docs
# Live computer dashboard: http://localhost:8000/dashboard

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List, Optional
from datetime import datetime

from database import init_db, get_db, Victim, Telemetry
from schemas import TelemetryCreate, TelemetryOut, VictimOut, VictimCreate
from auth import verify_api_key
import pool_zones
import triage

app = FastAPI(title="Triton Lifeband API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    init_db()


@app.post("/victims", response_model=VictimOut, dependencies=[Depends(verify_api_key)])
def create_victim(victim: VictimCreate, db: Session = Depends(get_db)):
    existing = db.query(Victim).filter(Victim.device_id == victim.device_id).first()
    if existing:
        raise HTTPException(status_code=400, detail="device_id already registered")

    if victim.id is not None:
        id_conflict = db.query(Victim).filter(Victim.id == victim.id).first()
        if id_conflict:
            raise HTTPException(
                status_code=400,
                detail=f"id {victim.id} is already in use by device_id '{id_conflict.device_id}'",
            )

    new_victim = Victim(
        id=victim.id,
        name=victim.name,
        device_id=victim.device_id,
        age_years=victim.age_years,
    )
    db.add(new_victim)
    db.commit()
    db.refresh(new_victim)
    return _victim_with_latest(new_victim, db)


@app.get("/victims", response_model=List[VictimOut])
def list_victims(db: Session = Depends(get_db)):
    victims = db.query(Victim).all()
    return [_victim_with_latest(v, db) for v in victims]


@app.get("/victims/{victim_id}", response_model=VictimOut)
def get_victim(victim_id: int, db: Session = Depends(get_db)):
    victim = db.query(Victim).filter(Victim.id == victim_id).first()
    if not victim:
        raise HTTPException(status_code=404, detail="Victim not found")
    return _victim_with_latest(victim, db)


@app.post("/victims/{victim_id}/acknowledge", response_model=VictimOut)
def acknowledge_victim(victim_id: int, db: Session = Depends(get_db)):
    victim = db.query(Victim).filter(Victim.id == victim_id).first()
    if not victim:
        raise HTTPException(status_code=404, detail="Victim not found")
    victim.acknowledged = True
    victim.acknowledged_at = datetime.utcnow()
    db.commit()
    db.refresh(victim)
    return _victim_with_latest(victim, db)


@app.post("/victims/{victim_id}/unacknowledge", response_model=VictimOut)
def unacknowledge_victim(victim_id: int, db: Session = Depends(get_db)):
    victim = db.query(Victim).filter(Victim.id == victim_id).first()
    if not victim:
        raise HTTPException(status_code=404, detail="Victim not found")
    victim.acknowledged = False
    victim.acknowledged_at = None
    db.commit()
    db.refresh(victim)
    return _victim_with_latest(victim, db)


@app.post("/telemetry", response_model=TelemetryOut, dependencies=[Depends(verify_api_key)])
def post_telemetry(reading: TelemetryCreate, db: Session = Depends(get_db)):
    victim = db.query(Victim).filter(Victim.device_id == reading.device_id).first()
    if not victim:
        raise HTTPException(
            status_code=404,
            detail=f"No victim registered with device_id '{reading.device_id}'. "
                   f"Register it first via POST /victims.",
        )

    previous_reading = (
        db.query(Telemetry)
        .filter(Telemetry.victim_id == victim.id)
        .order_by(desc(Telemetry.timestamp))
        .first()
    )

    new_reading = Telemetry(
        victim_id=victim.id,
        bpm=reading.bpm,
        piezo_depth=reading.piezo_depth,
        latitude=reading.latitude,
        longitude=reading.longitude,
        battery_pct=reading.battery_pct,
        sos=reading.sos or False,
        plr=reading.plr,
    )
    db.add(new_reading)
    db.commit()
    db.refresh(new_reading)

    return _build_telemetry_out(new_reading, victim, previous_reading)


@app.get("/victims/{victim_id}/telemetry", response_model=List[TelemetryOut])
def get_victim_telemetry(victim_id: int, limit: int = 100, db: Session = Depends(get_db)):
    victim = db.query(Victim).filter(Victim.id == victim_id).first()
    if not victim:
        raise HTTPException(status_code=404, detail="Victim not found")

    rows = (
        db.query(Telemetry)
        .filter(Telemetry.victim_id == victim_id)
        .order_by(desc(Telemetry.timestamp))
        .limit(limit + 1)
        .all()
    )

    results = []
    for i in range(min(limit, len(rows))):
        current = rows[i]
        previous = rows[i + 1] if i + 1 < len(rows) else None
        results.append(_build_telemetry_out(current, victim, previous))
    return results


@app.get("/", response_class=HTMLResponse)
def triton_landing():
    """Main entry point - the Texas county-level incident selector.
    Clicking a county with an active/monitored status opens /dashboard."""
    return TRITON_LANDING_HTML


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard():
    return DASHBOARD_HTML


TRITON_LANDING_HTML = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Triton Dashboard</title>
<style>
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    background: radial-gradient(ellipse at center, #0f1a24 0%, #0a0a0a 100%);
    color: #eee;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    display: flex; flex-direction: column; align-items: center;
    padding: 30px 20px;
  }
  h1 {
    font-size: 22px; letter-spacing: 3px; color: #00E5FF;
    margin: 0 0 6px 0; text-shadow: 0 0 20px rgba(0,229,255,0.4);
  }
  #legendRow { display: flex; gap: 20px; margin-bottom: 24px; font-size: 11px; color: #999; }
  .legend-item { display: flex; align-items: center; gap: 6px; }
  .legend-dot { width: 10px; height: 10px; border-radius: 50%; }

  #svgWrap { width: 100%; max-width: 720px; }
  svg { width: 100%; height: auto; overflow: visible; }

  .county-path {
    stroke: #1a1a1a; stroke-width: 0.6;
    transition: filter 0.15s, stroke-width 0.15s;
    cursor: default;
  }
  .county-path.clickable { cursor: pointer; }
  .county-path.clickable:hover { stroke: #00E5FF; stroke-width: 1.6; filter: brightness(1.3); }
  .county-active { animation: countyPulse 1.8s infinite; }
  @keyframes countyPulse {
    0% { filter: drop-shadow(0 0 2px #FF1744); }
    50% { filter: drop-shadow(0 0 10px #FF1744); }
    100% { filter: drop-shadow(0 0 2px #FF1744); }
  }

  #loadingMsg { color: #666; font-size: 13px; margin-top: 60px; }
</style>
</head>
<body>

<h1>TRITON DASHBOARD</h1>
<div id="legendRow">
  <div class="legend-item"><div class="legend-dot" style="background:#FF1744;"></div>Active Incident</div>
  <div class="legend-item"><div class="legend-dot" style="background:#FFEA00;"></div>Monitoring</div>
  <div class="legend-item"><div class="legend-dot" style="background:#3a3a3a;"></div>No Active Incident</div>
</div>

<div id="svgWrap">
  <div id="loadingMsg">Loading Texas outline...</div>
</div>

<script>
// Demo status data - in a real deployment this would come from the
// backend, keyed by county name. Hardcoded here since there's no
// per-county incident tracking on the backend yet.
var COUNTY_STATUS = {
  'Kerr': 'active',
  'Kendall': 'monitoring',
  'Gillespie': 'monitoring',
  'Bandera': 'monitoring',
  'Real': 'monitoring'
};

function statusColor(status) {
  if (status === 'active') return '#FF1744';
  if (status === 'monitoring') return '#FFEA00';
  return '#242424';
}

function ringToPath(ring, project) {
  var d = '';
  for (var i = 0; i < ring.length; i++) {
    var xy = project(ring[i][0], ring[i][1]);
    d += (i === 0 ? 'M' : 'L') + xy[0].toFixed(2) + ',' + xy[1].toFixed(2) + ' ';
  }
  return d + 'Z ';
}

function geometryToPath(geometry, project) {
  if (geometry.type === 'Polygon') {
    var d = '';
    for (var i = 0; i < geometry.coordinates.length; i++) {
      d += ringToPath(geometry.coordinates[i], project);
    }
    return d;
  }
  if (geometry.type === 'MultiPolygon') {
    var d2 = '';
    for (var p = 0; p < geometry.coordinates.length; p++) {
      for (var r = 0; r < geometry.coordinates[p].length; r++) {
        d2 += ringToPath(geometry.coordinates[p][r], project);
      }
    }
    return d2;
  }
  return '';
}

fetch('https://raw.githubusercontent.com/plotly/datasets/master/geojson-counties-fips.json')
  .then(function(res) {
    if (!res.ok) throw new Error('fetch failed: ' + res.status);
    return res.json();
  })
  .then(function(geojson) {
    var texasFeatures = geojson.features.filter(function(f) {
      return f.id && f.id.substring(0, 2) === '48';
    });

    // Compute bounding box across all Texas counties
    var minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
    texasFeatures.forEach(function(f) {
      var geom = f.geometry;
      var polys = geom.type === 'Polygon' ? [geom.coordinates] : geom.coordinates;
      polys.forEach(function(poly) {
        poly.forEach(function(ring) {
          ring.forEach(function(pt) {
            if (pt[0] < minLon) minLon = pt[0];
            if (pt[0] > maxLon) maxLon = pt[0];
            if (pt[1] < minLat) minLat = pt[1];
            if (pt[1] > maxLat) maxLat = pt[1];
          });
        });
      });
    });

    var avgLat = (minLat + maxLat) / 2;
    var lonScale = Math.cos(avgLat * Math.PI / 180);
    var lonRange = (maxLon - minLon) * lonScale;
    var latRange = (maxLat - minLat);
    var svgHeight = 700;
    var svgWidth = svgHeight * (lonRange / latRange);
    var pad = 20;

    function project(lon, lat) {
      var x = (lon - minLon) * lonScale / lonRange * (svgWidth - pad * 2) + pad;
      var y = (maxLat - lat) / latRange * (svgHeight - pad * 2) + pad;
      return [x, y];
    }

    var svgParts = ['<svg viewBox="0 0 ' + svgWidth.toFixed(0) + ' ' + svgHeight.toFixed(0) + '" xmlns="http://www.w3.org/2000/svg">'];

    texasFeatures.forEach(function(f) {
      var name = (f.properties && f.properties.NAME) || '';
      var status = COUNTY_STATUS[name] || 'none';
      var d = geometryToPath(f.geometry, project);
      var cls = 'county-path' + (status !== 'none' ? ' clickable' : '') + (status === 'active' ? ' county-active' : '');
      svgParts.push('<path class="' + cls + '" data-county="' + name + '" data-status="' + status +
        '" d="' + d + '" fill="' + statusColor(status) + '" fill-opacity="' + (status === 'none' ? '0.5' : '0.85') + '"><title>' +
        name + ' County' + (status !== 'none' ? ' - ' + status.toUpperCase() : '') + '</title></path>');
    });

    svgParts.push('</svg>');

    var wrap = document.getElementById('svgWrap');
    wrap.innerHTML = svgParts.join('');

    var paths = wrap.querySelectorAll('.county-path.clickable');
    paths.forEach(function(p) {
      p.addEventListener('click', function() {
        window.location.href = '/dashboard';
      });
    });
  })
  .catch(function(e) {
    document.getElementById('svgWrap').innerHTML =
      '<div id="loadingMsg">Could not load Texas outline (' + e.message + ').</div>';
  });
</script>

</body>
</html>
"""

DASHBOARD_HTML = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Triton Lifeband - Mission Control</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js"></script>
<style>
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body { background: #0d0d0d; color: #eee; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; padding: 20px; }
  h1 { font-size: 18px; letter-spacing: 1px; color: #00E5FF; margin: 0 0 4px 0; }
  #status { font-size: 12px; color: #888; margin-bottom: 16px; }
  .panel { background: #161616; border-radius: 10px; border: 1px solid #262626; padding: 14px; margin-bottom: 16px; }
  .panel h2 { font-size: 12px; letter-spacing: 1px; color: #999; margin: 0 0 10px 0; text-transform: uppercase; }

  .page-grid { display: grid; grid-template-columns: 2fr 1fr; gap: 16px; align-items: start; }

  /* Right column: maps at a modest fixed size, Victim Details flows
     naturally below the heatmap as a compact one-line bar. */
  .right-column { display: flex; flex-direction: column; gap: 16px; }
  .maps-stack { display: flex; flex-direction: column; gap: 16px; }
  .maps-stack .panel { display: flex; flex-direction: column; padding: 8px; margin-bottom: 0; }
  .maps-stack .panel h2 { padding: 6px 6px 0 6px; }
  #map, #heatmap { height: 420px; border-radius: 8px; cursor: pointer; }

  #victimDetailsFixed { padding: 10px 14px; }
  #victimDetailsPanel { overflow-x: auto; white-space: nowrap; }
  .details-line { display: inline-flex; align-items: center; gap: 10px; font-size: 12px; }
  .details-line .details-name { font-size: 13px; }
  .details-line .details-badge { font-size: 9px; padding: 2px 6px; }
  .details-line .details-metric { color: #ccc; }
  .details-line .details-metric b { color: #fff; }

  .map-fullscreen {
    position: fixed !important;
    top: 0 !important; left: 0 !important;
    width: 100vw !important; height: 100vh !important;
    z-index: 9999;
    border-radius: 0 !important;
  }
  .map-close-btn {
    display: none;
    position: fixed;
    top: 16px; right: 16px;
    z-index: 10001;
    background: #FF1744;
    color: #fff;
    border: none;
    border-radius: 6px;
    padding: 8px 14px;
    font-size: 13px;
    font-weight: bold;
    cursor: pointer;
  }
  .map-close-btn.visible { display: block; }

  /* Corner popup - ONLY shown while a map is fullscreen, fixed to a
     screen corner (not attached to the marker's position) */
  #mapCornerPopup {
    display: none;
    position: fixed;
    bottom: 24px;
    left: 24px;
    width: 420px;
    z-index: 10001;
    background: #1e1e1e;
    border-radius: 12px;
    border: 2px solid #333;
    padding: 22px;
    box-shadow: 0 6px 28px rgba(0,0,0,0.7);
  }
  #mapCornerPopup.visible { display: block; }
  #mapCornerPopup .popup-name { font-size: 20px; margin-bottom: 8px; }
  #mapCornerPopup .popup-badge { font-size: 12px; padding: 4px 10px; margin-bottom: 14px; }
  #mapCornerPopup .popup-grid { gap: 10px; margin-bottom: 10px; }
  #mapCornerPopup .popup-metric { padding: 10px 12px; }
  #mapCornerPopup .popup-metric-label { font-size: 10px; }
  #mapCornerPopup .popup-metric-value { font-size: 19px; }
  #mapCornerPopup .popup-location { font-size: 13px; }

  .top-bar { display: flex; gap: 16px; margin-bottom: 16px; flex-wrap: wrap; }
  .top-bar-item { background: #161616; border: 1px solid #262626; border-radius: 8px; padding: 8px 14px; font-size: 12px; color: #ccc; }
  #opClock { color: #00E5FF; font-weight: bold; }

  .panel-controls { display: flex; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
  .panel-controls select { background: #1e1e1e; color: #eee; border: 1px solid #333; border-radius: 5px; padding: 4px 8px; font-size: 11px; }
  #radiusInstructions { font-size: 11px; color: #00E5FF; }

  .action-btn { background: #262626; color: #eee; border: 1px solid #444; border-radius: 5px; padding: 5px 10px; font-size: 11px; cursor: pointer; margin-right: 6px; margin-top: 8px; }
  .action-btn:hover { background: #333; }
  .action-btn.acknowledged { background: #1a3a1a; border-color: #2a5a2a; color: #7fdb7f; }
  .row-ack-btn { font-size: 10px; margin-left: 8px; cursor: pointer; color: #666; }
  .row-ack-btn.acknowledged { color: #7fdb7f; }
  .p1-badge { background: #FF1744; color: #fff; font-size: 9px; font-weight: bold; padding: 2px 6px; border-radius: 4px; margin-left: 6px; animation: pulse 1.4s infinite; }

  .numbered-marker-wrap { position: relative; width: 34px; height: 46px; }
  .marker-heading { position: absolute; top: -4px; left: 13px; width: 0; height: 0; border-left: 4px solid transparent; border-right: 4px solid transparent; border-bottom: 9px solid #fff; transform-origin: 4px 25px; }
  .map-pin {
    position: absolute; top: 4px; left: 2px;
    width: 30px; height: 30px;
    border-radius: 50% 50% 50% 0;
    transform: rotate(-45deg);
    border: 2px solid rgba(255,255,255,0.85);
    box-shadow: 0 2px 6px rgba(0,0,0,0.5);
  }
  .pin-number {
    position: absolute; top: 7px; left: 2px;
    width: 30px; height: 30px;
    display: flex; align-items: center; justify-content: center;
    font-size: 10px; font-weight: bold; color: #000;
  }

  .details-empty { color: #666; font-size: 12px; padding: 12px 4px; }
  .details-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; padding: 0 4px; }
  .details-name { font-size: 14px; font-weight: bold; }
  .details-badge { font-size: 10px; font-weight: bold; padding: 3px 8px; border-radius: 5px; color: #000; }
  .details-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
  .details-card { background: #1e1e1e; border-radius: 8px; padding: 10px; }
  .details-card-label { font-size: 9px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; }
  .details-card-value { font-size: 16px; font-weight: bold; }
  .details-location { grid-column: 1 / 3; font-size: 11px; color: #aaa; margin-top: 2px; }

  .popup-name { font-size: 13px; font-weight: bold; margin-bottom: 4px; }
  .popup-badge { display: inline-block; font-size: 9px; font-weight: bold; padding: 2px 6px; border-radius: 4px; margin-bottom: 8px; color: #000; }
  .popup-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin-bottom: 6px; }
  .popup-metric { background: #262626; border-radius: 5px; padding: 5px 7px; }
  .popup-metric-label { font-size: 8px; color: #888; text-transform: uppercase; }
  .popup-metric-value { font-size: 13px; font-weight: bold; }
  .popup-location { font-size: 10px; color: #aaa; }

  .dispatch-row { display: flex; justify-content: space-between; align-items: center; padding: 5px 0; border-bottom: 1px solid #262626; font-size: 12px; }
  .dispatch-team { background: #00E5FF; color: #000; font-weight: bold; padding: 2px 8px; border-radius: 5px; font-size: 11px; }
  .dispatch-target { color: #FF1744; font-weight: bold; }
  #dispatchEmpty { color: #666; font-size: 12px; padding: 6px 0; }
  .show-more-link { color: #00E5FF; font-size: 12px; cursor: pointer; padding-top: 8px; display: inline-block; }
  .show-more-link:hover { text-decoration: underline; }

  .top5-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .top5-col-header { font-size: 12px; font-weight: bold; margin-bottom: 8px; }
  .top5-col-header.critical { color: #FF1744; }
  .top5-col-header.warning { color: #FFEA00; }
  .top5-row { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px solid #262626; font-size: 12px; cursor: pointer; }
  .top5-row:hover { background: #1e1e1e; }
  .top5-row.selected { background: #202b2e; outline: 1px solid #00E5FF; }
  .top5-empty { color: #666; font-size: 12px; }

  #sosSection {
    background: #3a0010;
    border: 2px solid #FF1744;
    border-radius: 10px;
    padding: 14px 18px;
    margin-bottom: 16px;
    animation: pulse 1.4s infinite;
  }
  #sosSection.sos-idle { background: #1a1a1a; border-color: #333; animation: none; }
  #sosSection.sos-idle h2 { color: #888; }
  .sos-idle-msg { color: #666; font-size: 12px; }
  @keyframes pulse { 0% { box-shadow: 0 0 0 0 rgba(255,23,68,0.5); } 70% { box-shadow: 0 0 0 12px rgba(255,23,68,0); } 100% { box-shadow: 0 0 0 0 rgba(255,23,68,0); } }
  #sosSection h2 { color: #FF1744; font-size: 14px; margin: 0 0 8px 0; }
  .sos-item { display: inline-block; background: #FF1744; color: #000; font-weight: bold; padding: 6px 12px; border-radius: 6px; margin: 4px 6px 4px 0; font-size: 13px; cursor: pointer; }
  .sos-item:hover { opacity: 0.85; }

  .section-note { font-size: 11px; color: #666; margin: -4px 0 12px 2px; font-style: italic; }
  .section { margin-bottom: 16px; border-radius: 8px; border: 2px solid; overflow: hidden; }
  .section-header { padding: 8px 12px; font-weight: bold; font-size: 12px; letter-spacing: 0.5px; display: flex; justify-content: space-between; align-items: center; cursor: pointer; }
  .section-offline { border-color: #888; }
  .section-offline .section-header { background: rgba(136,136,136,0.15); color: #ccc; }
  .section-critical { border-color: #FF1744; }
  .section-critical .section-header { background: rgba(255,23,68,0.15); color: #FF1744; }
  .section-warning { border-color: #FFEA00; }
  .section-warning .section-header { background: rgba(255,234,0,0.15); color: #FFEA00; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th, td { padding: 7px 9px; text-align: left; border-bottom: 1px solid #2a2a2a; white-space: nowrap; }
  th { background: #1a1a1a; color: #999; font-weight: normal; font-size: 10px; cursor: pointer; user-select: none; position: sticky; top: 0; }
  th:hover { color: #00E5FF; background: #222; }
  th .arrow { font-size: 9px; margin-left: 3px; opacity: 0.6; }
  tr { transition: background 0.1s; }
  tr:hover { background: #202020; outline: 1px solid #333; }
  .bool-true { color: #FF1744; font-weight: bold; }
  .bool-false { color: #555; }
  #empty { padding: 40px; text-align: center; color: #666; }
</style>
</head>
<body>

<button class="map-close-btn" id="mapCloseBtn">CLOSE (ESC)</button>
<div id="mapCornerPopup"></div>

<h1>TRITON LIFEBAND - MISSION CONTROL</h1>
<div id="status">Loading...</div>
<div class="top-bar">
  <a href="/" class="top-bar-item" id="homeBtn" style="text-decoration:none; color:#00E5FF; cursor:pointer;">&larr; Home</a>
  <div class="top-bar-item" id="opClock">No active distress signals yet</div>
  <div class="top-bar-item" id="weatherWidget">Loading weather...</div>
</div>

<div class="page-grid">
  <div class="left-column">

    <div class="panel">
      <h2>SAR Dispatch Recommendations</h2>
      <div id="dispatchList"></div>
      <div id="dispatchToggle"></div>
    </div>

    <div class="panel">
      <h2>Most Urgent - Critical &amp; Warning (click a name for details)</h2>
      <div class="top5-grid">
        <div>
          <div class="top5-col-header critical">CRITICAL DISTRESS</div>
          <div id="top5Critical"></div>
        </div>
        <div>
          <div class="top5-col-header warning">WARNING</div>
          <div id="top5Warning"></div>
        </div>
      </div>
    </div>

    <div id="fullSections"></div>

  </div>

  <div class="right-column">
    <div class="maps-stack">
      <div class="panel">
        <h2>Victim Locations (click to expand)</h2>
        <div class="panel-controls">
          <select id="sarRadius">
            <option value="0">SAR radius: none</option>
            <option value="100">100m</option>
            <option value="500">500m</option>
            <option value="1000">1km</option>
            <option value="2000">2km</option>
            <option value="5000">5km</option>
          </select>
          <button class="action-btn" id="resetLocationBtn" style="margin-top:0;">Reset My Location</button>
          <span id="radiusInstructions"></span>
        </div>
        <div id="map"></div>
      </div>
      <div class="panel">
        <h2>Urgency Heatmap (click to expand)</h2>
        <div class="panel-controls">
          <select id="heatmapCriteria">
            <option value="all">Show All</option>
            <option value="victim">Victim Concentration</option>
            <option value="critical">Criticality Concentration</option>
            <option value="sos">SOS Concentration</option>
            <option value="age">Age-Based Concentration</option>
            <option value="water">Water Level Rise Concentration</option>
          </select>
        </div>
        <div id="heatmap"></div>
      </div>
      <div class="panel" id="victimDetailsFixed">
        <h2>Victim Details</h2>
        <div id="victimDetailsPanel">
          <div class="details-empty">Click a victim on the map or in the Most Urgent list to see their details here.</div>
        </div>
      </div>
    </div>
  </div>

</div>

<div id="empty" style="display:none;">No victims registered yet.</div>

<script>
var YELLOW_THRESHOLD = 33;
var RED_THRESHOLD = 66;
var OFFLINE_THRESHOLD_SEC = 60;
var SEARCH_CENTER = [26.5, -90.5];

var COLUMNS = [
  ['victim_id', 'victim_id'], ['reported_at', 'reported_at'], ['elapsed_min', 'elapsed_min'],
  ['latitude', 'latitude'], ['longitude', 'longitude'], ['age_years', 'age_years'],
  ['bpm', 'bpm'], ['bpm_critical', 'bpm_critical'], ['depth_m', 'depth_m'],
  ['rise_rate_m_per_min', 'rise_rate_m_per_min'], ['hours_to_critical_depth', 'hours_to_critical_depth'],
  ['battery_pct', 'battery_pct'], ['battery_low', 'battery_low'],
  ['age_vulnerability', 'age_vulnerability'], ['urgency_score', 'urgency_score']
];

var sortState = {
  offline: {field: 'elapsed_min', asc: false},
  critical: {field: 'urgency_score', asc: false},
  warning: {field: 'urgency_score', asc: false}
};

var uiState = {
  dispatchExpanded: false,
  criticalExpanded: false,
  warningExpanded: false,
  selectedVictimId: null
};

var latestRows = [];
var map, heatmapInstance, heatLayer;
var mapMarkers = {};
var currentFullscreenMap = null;
var mapHasBeenFitted = false;
var heatmapHasBeenFitted = false;

// Must match the backend's TRITON_API_KEY env var (or its dev default) -
// needed for the Assign/Claim buttons, which POST to the acknowledge
// endpoints.
var API_KEY = 'dev-key-change-me';

var previousPositions = {}; // victim_id -> {lat, lng} from last refresh, for heading vectors
var previousPlr = {};       // victim_id -> last plr value, for detecting an increasing trend
var operationStartTime = null;
var currentHeatCriteria = 'all';
var radiusSelectMode = false;
var radiusCircle = null;
var radiusCenterMarker = null;
var dispatcherMarker = null;
var routeLine = null;
var dispatcherLocation = null; // {lat, lng} set by clicking the map
var settingDispatcherLocation = false;
var pendingRouteVictim = null;
var selectedRadius = 0;

function initMaps() {
  map = L.map('map').setView(SEARCH_CENTER, 12);
  L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    attribution: 'Tiles - Esri, Maxar, Earthstar Geographics', maxZoom: 19
  }).addTo(map);

  heatmapInstance = L.map('heatmap').setView(SEARCH_CENTER, 12);
  L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    attribution: 'Tiles - Esri, Maxar, Earthstar Geographics', maxZoom: 19
  }).addTo(heatmapInstance);

  map.on('click', function(e) {
    if (settingDispatcherLocation) {
      dispatcherLocation = {lat: e.latlng.lat, lng: e.latlng.lng};
      settingDispatcherLocation = false;
      if (dispatcherMarker) map.removeLayer(dispatcherMarker);
      dispatcherMarker = L.circleMarker([dispatcherLocation.lat, dispatcherLocation.lng], {
        radius: 9, color: '#00E5FF', fillColor: '#00E5FF', fillOpacity: 1, weight: 3
      }).addTo(map);
      dispatcherMarker.bindTooltip('You (Dispatcher)', {permanent: false});
      if (pendingRouteVictim) {
        renderRoute(dispatcherLocation.lat, dispatcherLocation.lng, pendingRouteVictim);
        pendingRouteVictim = null;
      }
      return;
    }
    if (radiusSelectMode) {
      placeRadiusCenter(e.latlng);
      radiusSelectMode = false;
      return;
    }
    toggleMapFullscreen('map', map);
  });
  heatmapInstance.on('click', function() { toggleMapFullscreen('heatmap', heatmapInstance); });

  document.getElementById('mapCloseBtn').addEventListener('click', closeAnyFullscreenMap);
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeAnyFullscreenMap();
  });

  document.getElementById('heatmapCriteria').addEventListener('change', function(e) {
    currentHeatCriteria = e.target.value;
    updateMap(latestRows);
  });

  document.getElementById('sarRadius').addEventListener('change', function(e) {
    selectedRadius = parseInt(e.target.value, 10);
    if (selectedRadius > 0) {
      radiusSelectMode = true;
      document.getElementById('radiusInstructions').textContent = 'Click the map to place center';
    } else {
      radiusSelectMode = false;
      if (radiusCircle) { map.removeLayer(radiusCircle); radiusCircle = null; }
      if (radiusCenterMarker) { map.removeLayer(radiusCenterMarker); radiusCenterMarker = null; }
      document.getElementById('radiusInstructions').textContent = '';
    }
  });

  document.getElementById('resetLocationBtn').addEventListener('click', resetDispatcherLocation);

  setInterval(updateClock, 1000);
  fetchWeather();
  setInterval(fetchWeather, 600000);
}

function toggleMapFullscreen(divId, leafletInstance) {
  var el = document.getElementById(divId);
  if (currentFullscreenMap === divId) {
    closeAnyFullscreenMap();
    return;
  }
  if (currentFullscreenMap) closeAnyFullscreenMap();

  el.classList.add('map-fullscreen');
  document.getElementById('mapCloseBtn').classList.add('visible');
  currentFullscreenMap = divId;
  setTimeout(function() { leafletInstance.invalidateSize(); }, 150);
}

function closeAnyFullscreenMap() {
  if (!currentFullscreenMap) return;
  document.getElementById(currentFullscreenMap).classList.remove('map-fullscreen');
  document.getElementById('mapCloseBtn').classList.remove('visible');
  hideCornerPopup();
  var instance = currentFullscreenMap === 'map' ? map : heatmapInstance;
  currentFullscreenMap = null;
  setTimeout(function() { instance.invalidateSize(); }, 150);
}

function bucketColor(bucket) {
  if (bucket === 'critical') return '#FF1744';
  if (bucket === 'warning') return '#FFEA00';
  return '#888888';
}

function bandNumber(victimId) {
  var digits = victimId.replace(/[^0-9]/g, '');
  return digits || victimId;
}

function createNumberedIcon(row, bearing) {
  var arrowHtml = bearing != null ? '<div class="marker-heading" style="transform: rotate(' + bearing + 'deg)"></div>' : '';
  var pinColor = row.is_p1 ? '#fff' : bucketColor(row.bucket);
  var borderStyle = row.is_p1 ? 'border: 3px solid #FF1744;' : '';
  var html = '<div class="numbered-marker-wrap">' + arrowHtml +
    '<div class="map-pin" style="background:' + pinColor + ';' + borderStyle + '"></div>' +
    '<div class="pin-number">' + bandNumber(row.victim_id) + '</div></div>';
  // Anchor at the pin's bottom point (not the wrapper's center), so the
  // actual tip - not the middle of the shape - marks the true coordinate.
  return L.divIcon({ className: '', html: html, iconSize: [34, 46], iconAnchor: [17, 44] });
}

function buildCornerPopupHtml(row) {
  var badgeColor = bucketColor(row.bucket);
  var loc = row.latitude !== '-' ? (row.latitude + ', ' + row.longitude) : 'No GPS fix';
  var p1Badge = row.is_p1 ? '<span class="p1-badge">P1 - LOSING SIGNAL</span>' : '';
  return '' +
    '<div class="popup-name">' + row.victim_id + p1Badge + '</div>' +
    '<div class="popup-badge" style="background:' + badgeColor + '">' + row.bucket.toUpperCase() + '</div>' +
    '<div class="popup-grid">' +
      '<div class="popup-metric"><div class="popup-metric-label">Heart Rate</div><div class="popup-metric-value">' + (row.bpm !== '-' ? row.bpm + ' bpm' : '-') + '</div></div>' +
      '<div class="popup-metric"><div class="popup-metric-label">Depth</div><div class="popup-metric-value">' + (row.depth_m !== '-' ? row.depth_m + ' m' : '-') + '</div></div>' +
      '<div class="popup-metric"><div class="popup-metric-label">Battery</div><div class="popup-metric-value">' + (row.battery_pct !== '-' ? row.battery_pct + '%' : '-') + '</div></div>' +
      '<div class="popup-metric"><div class="popup-metric-label">Urgency</div><div class="popup-metric-value">' + row.urgency_score + '</div></div>' +
    '</div>' +
    '<div class="popup-location">' + loc + '</div>';
}

// Draws a straight-line path on the Locations map from the dispatcher's
// own marked position to the victim - a straight line is the technically
// correct thing to show here, since the search area is open water with
// no road network to route through.
//
// Uses a manual "click the map to mark your position" flow instead of
// browser geolocation, since that requires HTTPS/localhost and permission
// grants that don't reliably work across setups. Once set, your position
// is remembered for subsequent route requests until you reset it.
function drawRouteToVictim(row) {
  if (row.lat == null || row.lng == null) {
    document.getElementById('radiusInstructions').textContent = 'This victim has no GPS fix yet.';
    return;
  }

  if (dispatcherLocation) {
    renderRoute(dispatcherLocation.lat, dispatcherLocation.lng, row);
    return;
  }

  pendingRouteVictim = row;
  settingDispatcherLocation = true;
  document.getElementById('radiusInstructions').textContent = 'Click the map to mark your current location';
  if (currentFullscreenMap !== 'map') {
    toggleMapFullscreen('map', map);
  }
}

function resetDispatcherLocation() {
  dispatcherLocation = null;
  if (dispatcherMarker) { map.removeLayer(dispatcherMarker); dispatcherMarker = null; }
  if (routeLine) { map.removeLayer(routeLine); routeLine = null; }
  document.getElementById('radiusInstructions').textContent = 'Your location cleared.';
}

function renderRoute(dispatcherLat, dispatcherLng, row) {
  if (routeLine) map.removeLayer(routeLine);

  routeLine = L.polyline(
    [[dispatcherLat, dispatcherLng], [row.lat, row.lng]],
    { color: '#00E5FF', weight: 3, dashArray: '8,6' }
  ).addTo(map);

  var distanceM = haversineMeters(dispatcherLat, dispatcherLng, row.lat, row.lng);
  document.getElementById('radiusInstructions').textContent =
    'Path to ' + row.victim_id + ': ' + formatRadius(Math.round(distanceM)) +
    ' (click "Reset My Location" below to re-mark your position)';

  map.fitBounds([[dispatcherLat, dispatcherLng], [row.lat, row.lng]], {padding: [50, 50], maxZoom: 15});
}

function appendActionButtons(container, row) {
  var dirBtn = document.createElement('button');
  dirBtn.className = 'action-btn';
  dirBtn.textContent = 'Show Path to Victim';
  if (row.lat == null) dirBtn.disabled = true;
  dirBtn.addEventListener('click', function() { drawRouteToVictim(row); });
  container.appendChild(dirBtn);

  var ackBtn = document.createElement('button');
  ackBtn.className = 'action-btn' + (row.acknowledged ? ' acknowledged' : '');
  ackBtn.textContent = row.acknowledged ? 'Assigned (click to unassign)' : 'Assign to Dispatcher';
  ackBtn.addEventListener('click', function() { toggleAcknowledge(row.db_id, row.acknowledged); });
  container.appendChild(ackBtn);
}

function showCornerPopup(row) {
  var el = document.getElementById('mapCornerPopup');
  el.innerHTML = buildCornerPopupHtml(row);
  appendActionButtons(el, row);
  el.classList.add('visible');
}

function hideCornerPopup() {
  document.getElementById('mapCornerPopup').classList.remove('visible');
}

function selectVictim(victimId, shouldPanMap) {
  uiState.selectedVictimId = victimId;
  updateDetailsPanel();
  var row = latestRows.filter(function(r) { return r.victim_id === victimId; })[0];
  if (shouldPanMap && row && row.lat != null && row.lng != null) {
    map.setView([row.lat, row.lng], 15);
  }
  // Corner popup only appears when the Locations map is fullscreen.
  if (currentFullscreenMap === 'map' && row) {
    showCornerPopup(row);
  }
}

function updateDetailsPanel() {
  var panel = document.getElementById('victimDetailsPanel');
  panel.innerHTML = '';

  var row = latestRows.filter(function(r) { return r.victim_id === uiState.selectedVictimId; })[0];
  if (!row) {
    var emptyDiv = document.createElement('div');
    emptyDiv.className = 'details-empty';
    emptyDiv.textContent = 'Click a victim on the map or in the Most Urgent list to see their details here.';
    panel.appendChild(emptyDiv);
    return;
  }

  var header = document.createElement('div');
  header.className = 'details-header';
  var nameEl = document.createElement('div');
  nameEl.className = 'details-name';
  nameEl.textContent = row.victim_id;
  if (row.is_p1) {
    var p1Badge = document.createElement('span');
    p1Badge.className = 'p1-badge';
    p1Badge.textContent = 'P1 - LOSING SIGNAL';
    nameEl.appendChild(p1Badge);
  }
  var badge = document.createElement('div');
  badge.className = 'details-badge';
  badge.style.background = bucketColor(row.bucket);
  badge.textContent = row.bucket.toUpperCase();
  header.appendChild(nameEl);
  header.appendChild(badge);
  panel.appendChild(header);

  var grid = document.createElement('div');
  grid.className = 'details-grid';

  function metricCard(label, value) {
    var card = document.createElement('div');
    card.className = 'details-card';
    var lbl = document.createElement('div');
    lbl.className = 'details-card-label';
    lbl.textContent = label;
    var val = document.createElement('div');
    val.className = 'details-card-value';
    val.textContent = value;
    card.appendChild(lbl);
    card.appendChild(val);
    return card;
  }

  grid.appendChild(metricCard('Heart Rate', row.bpm !== '-' ? row.bpm + ' bpm' : '-'));
  grid.appendChild(metricCard('Depth', row.depth_m !== '-' ? row.depth_m + ' m' : '-'));
  grid.appendChild(metricCard('Battery', row.battery_pct !== '-' ? row.battery_pct + '%' : '-'));
  grid.appendChild(metricCard('Urgency', row.urgency_score));

  var locationDiv = document.createElement('div');
  locationDiv.className = 'details-location';
  locationDiv.textContent = row.latitude !== '-' ? ('Location: ' + row.latitude + ', ' + row.longitude) : 'Location: no GPS fix';
  grid.appendChild(locationDiv);

  panel.appendChild(grid);
  appendActionButtons(panel, row);
}

function heatWeight(row, criteria) {
  if (criteria === 'critical') return row.bucket === 'critical' ? 1.0 : 0.05;
  if (criteria === 'sos') return row.sos ? 1.0 : 0.02;
  if (criteria === 'age') {
    var age = row.age_raw;
    if (age == null) return 0.1;
    return (age < 12 || age > 65) ? 1.0 : 0.3;
  }
  if (criteria === 'water') {
    var rr = row.rise_rate_raw;
    if (rr == null) return 0.1;
    return Math.min(1.0, Math.max(0.1, rr * 50));
  }
  // 'all' / 'victim' / default - urgency-weighted
  return Math.max(0.1, row.urgency_raw / 100);
}

function updateMap(rows) {
  var withFix = rows.filter(function(r) { return r.lat != null && r.lng != null; });
  Object.keys(mapMarkers).forEach(function(k) { map.removeLayer(mapMarkers[k]); });
  mapMarkers = {};

  var newPreviousPositions = {};
  var newPreviousPlr = {};

  withFix.forEach(function(r) {
    var prevPos = previousPositions[r.victim_id];
    var bearing = null;
    if (prevPos && (prevPos.lat !== r.lat || prevPos.lng !== r.lng)) {
      bearing = computeBearing(prevPos.lat, prevPos.lng, r.lat, r.lng);
    }
    newPreviousPositions[r.victim_id] = {lat: r.lat, lng: r.lng};
    if (r.plr_raw != null) newPreviousPlr[r.victim_id] = r.plr_raw;

    var marker = L.marker([r.lat, r.lng], { icon: createNumberedIcon(r, bearing) }).addTo(map);
    marker.bindTooltip(r.victim_id + ' (' + r.urgency_score + ')' + (r.is_p1 ? ' - P1' : ''), {permanent: false});
    marker.on('click', function() { selectVictim(r.victim_id, false); });
    mapMarkers[r.victim_id] = marker;
  });

  previousPositions = newPreviousPositions;
  previousPlr = newPreviousPlr;

  if (withFix.length > 0 && !mapHasBeenFitted) {
    map.fitBounds(withFix.map(function(r) { return [r.lat, r.lng]; }), {padding: [30, 30], maxZoom: 15});
    mapHasBeenFitted = true;
  }

  // Refresh the corner popup's content (if open) with live data, since
  // markers get rebuilt every refresh - keeps numbers updating instead of
  // going stale or disappearing.
  if (currentFullscreenMap === 'map' && uiState.selectedVictimId) {
    var selRow = withFix.filter(function(r) { return r.victim_id === uiState.selectedVictimId; })[0];
    if (selRow) showCornerPopup(selRow); else hideCornerPopup();
  }

  if (heatLayer) heatmapInstance.removeLayer(heatLayer);
  var heatPoints = withFix.map(function(r) { return [r.lat, r.lng, heatWeight(r, currentHeatCriteria)]; });
  heatLayer = L.heatLayer(heatPoints, {radius: 35, blur: 25, maxZoom: 15}).addTo(heatmapInstance);
  if (withFix.length > 0 && !heatmapHasBeenFitted) {
    heatmapInstance.fitBounds(withFix.map(function(r) { return [r.lat, r.lng]; }), {padding: [30, 30], maxZoom: 15});
    heatmapHasBeenFitted = true;
  }
}

function computeBearing(lat1, lon1, lat2, lon2) {
  var toRad = function(d) { return d * Math.PI / 180; };
  var toDeg = function(r) { return r * 180 / Math.PI; };
  var dLon = toRad(lon2 - lon1);
  var y = Math.sin(dLon) * Math.cos(toRad(lat2));
  var x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) - Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  var R = 6371000;
  var toRad = function(d) { return d * Math.PI / 180; };
  var dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatRadius(m) {
  return m >= 1000 ? (m / 1000) + 'km' : m + 'm';
}

function countVictimsInRadius(center, radiusM) {
  return latestRows.filter(function(r) {
    if (r.lat == null || r.lng == null) return false;
    return haversineMeters(center.lat, center.lng, r.lat, r.lng) <= radiusM;
  }).length;
}

function placeRadiusCenter(latlng) {
  if (radiusCircle) map.removeLayer(radiusCircle);
  if (radiusCenterMarker) map.removeLayer(radiusCenterMarker);
  radiusCircle = L.circle(latlng, {radius: selectedRadius, color: '#00E5FF', fillOpacity: 0.08}).addTo(map);
  radiusCenterMarker = L.marker(latlng).addTo(map);
  var count = countVictimsInRadius(latlng, selectedRadius);
  document.getElementById('radiusInstructions').textContent = count + ' victim(s) within ' + formatRadius(selectedRadius);
}

// Assign/Claim - persists to the backend so multiple dispatchers see the
// same "already being handled" state, not just whichever screen clicked it.
function toggleAcknowledge(dbId, currentlyAcknowledged) {
  var endpoint = currentlyAcknowledged ? 'unacknowledge' : 'acknowledge';
  fetch('/victims/' + dbId + '/' + endpoint, {
    method: 'POST',
    headers: {'X-API-Key': API_KEY}
  }).then(function() { fetchData(); }).catch(function(e) { console.error('Acknowledge failed:', e); });
}

function checkOperationStart(rows) {
  if (operationStartTime) return;
  var hasDistress = rows.some(function(r) { return r.bucket === 'critical' || r.sos; });
  if (hasDistress) operationStartTime = new Date();
}

function updateClock() {
  var el = document.getElementById('opClock');
  if (!operationStartTime) { el.textContent = 'No active distress signals yet'; return; }
  var elapsed = Math.floor((new Date() - operationStartTime) / 1000);
  var h = Math.floor(elapsed / 3600), m = Math.floor((elapsed % 3600) / 60), s = elapsed % 60;
  function pad(n) { return n < 10 ? '0' + n : '' + n; }
  el.textContent = 'SAR Operation Time: ' + pad(h) + ':' + pad(m) + ':' + pad(s);
}

// Weather - NOAA's api.weather.gov, free and no API key required for US
// coastal/marine waters. Falls back gracefully if this remote offshore
// point isn't covered or the request fails for any reason.
function fetchWeather() {
  var el = document.getElementById('weatherWidget');
  fetch('https://api.weather.gov/points/' + SEARCH_CENTER[0] + ',' + SEARCH_CENTER[1])
    .then(function(res) {
      if (!res.ok) throw new Error('points lookup failed');
      return res.json();
    })
    .then(function(pointData) {
      return fetch(pointData.properties.forecast);
    })
    .then(function(res) {
      if (!res.ok) throw new Error('forecast fetch failed');
      return res.json();
    })
    .then(function(forecastData) {
      var period = forecastData.properties.periods[0];
      el.textContent = 'Weather: ' + period.temperature + '\u00b0' + period.temperatureUnit +
        ' - ' + period.shortForecast + ' - Wind ' + period.windSpeed + ' ' + period.windDirection;
    })
    .catch(function() {
      el.textContent = 'Weather data unavailable for this location.';
    });
}

function computeRow(v) {
  var t = v.latest_telemetry;
  var now = new Date();
  var reportedAt = t ? new Date(t.timestamp) : null;
  var elapsedSec = reportedAt ? Math.round((now - reportedAt) / 1000) : null;
  var elapsedMin = elapsedSec != null ? Math.round(elapsedSec / 60) : null;

  var bpm = t ? t.bpm : null;
  var bpmCritical = t ? (bpm > 140 || (bpm < 45 && bpm > 0)) : false;
  var deepWater = t ? (t.piezo_depth > 3500) : false;
  var batteryLow = t && t.battery_pct != null ? (t.battery_pct < 20) : false;
  var isOffline = t == null || (elapsedSec != null && elapsedSec > OFFLINE_THRESHOLD_SEC);
  var urgency = t ? t.urgency_score : -1;
  var sos = t ? !!t.sos : false;
  var plrRaw = t && t.plr != null ? t.plr : null;

  var bucket;
  if (isOffline) { bucket = 'offline'; }
  else if (urgency >= RED_THRESHOLD) { bucket = 'critical'; }
  else { bucket = 'warning'; }

  // P1: LoRa packet loss rate is increasing AND depth is high - this
  // victim may lose connectivity soon, so treat as top priority now while
  // we can still reach them. plr is currently simulated (see
  // simulate_live_data.py) until real gateway firmware tracks it.
  var depthM = t ? t.depth_m : null;
  var prevPlr = previousPlr[v.name];
  var plrIncreasing = plrRaw != null && prevPlr != null && plrRaw > prevPlr;
  var isP1 = plrIncreasing && depthM != null && depthM > 2.5;

  var flags = [];
  if (sos) flags.push('SOS');
  if (isP1) flags.push('P1 - LOSING SIGNAL');
  if (bpmCritical) flags.push('Critical BPM');
  if (deepWater) flags.push('Deep Water');
  if (batteryLow) flags.push('Low Battery');
  if (isOffline) flags.push('No Recent Signal');
  var status = flags.length ? flags.join(' / ') : 'Reporting';

  return {
    bucket: bucket, sos: sos, is_p1: isP1, urgency_raw: urgency, elapsed_raw: elapsedMin != null ? elapsedMin : 999999,
    lat: t ? t.latitude : null, lng: t ? t.longitude : null,
    db_id: v.id, acknowledged: !!v.acknowledged,
    victim_id: v.name,
    reported_at: reportedAt ? reportedAt.toLocaleString() : 'Never',
    elapsed_min: elapsedMin != null ? elapsedMin : '-',
    latitude: t && t.latitude != null ? t.latitude.toFixed(6) : '-',
    longitude: t && t.longitude != null ? t.longitude.toFixed(6) : '-',
    age_years: v.age_years != null ? v.age_years : '-',
    age_raw: v.age_years,
    bpm: t ? t.bpm.toFixed(1) : '-',
    bpm_critical: bpmCritical,
    depth_m: t ? t.depth_m.toFixed(2) : '-',
    rise_rate_m_per_min: t && t.rise_rate_m_per_hr != null ? (t.rise_rate_m_per_hr / 60).toFixed(4) : '-',
    rise_rate_raw: t && t.rise_rate_m_per_hr != null ? (t.rise_rate_m_per_hr / 60) : null,
    hours_to_critical_depth: t && t.hours_to_critical_depth != null ? t.hours_to_critical_depth.toFixed(2) : '-',
    battery_pct: t && t.battery_pct != null ? t.battery_pct.toFixed(0) : '-',
    battery_low: batteryLow,
    age_vulnerability: t ? t.age_vulnerability.toFixed(2) : '-',
    urgency_score: t ? t.urgency_score.toFixed(1) : '-',
    plr_raw: plrRaw,
    plr: plrRaw != null ? (plrRaw * 100).toFixed(0) + '%' : '-',
    status: status
  };
}

function sortValue(row, field) {
  if (field === 'urgency_score') return row.urgency_raw;
  if (field === 'elapsed_min') return row.elapsed_raw;
  var v = row[field];
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (typeof v === 'string' && v !== '-' && !isNaN(parseFloat(v))) return parseFloat(v);
  return v;
}

function buildSectionTable(key, rows) {
  var state = sortState[key];
  var sorted = rows.slice().sort(function(a, b) {
    var av = sortValue(a, state.field), bv = sortValue(b, state.field);
    if (av < bv) return state.asc ? -1 : 1;
    if (av > bv) return state.asc ? 1 : -1;
    return 0;
  });

  var table = document.createElement('table');
  var thead = document.createElement('thead');
  var headRow = document.createElement('tr');

  COLUMNS.forEach(function(col) {
    var th = document.createElement('th');
    th.textContent = col[1];
    if (state.field === col[0]) {
      var arrowSpan = document.createElement('span');
      arrowSpan.className = 'arrow';
      arrowSpan.textContent = state.asc ? '^' : 'v';
      th.appendChild(arrowSpan);
    }
    th.addEventListener('click', function() {
      if (sortState[key].field === col[0]) {
        sortState[key].asc = !sortState[key].asc;
      } else {
        sortState[key].field = col[0];
        sortState[key].asc = true;
      }
      render(latestRows);
    });
    headRow.appendChild(th);
  });
  var assignTh = document.createElement('th');
  assignTh.textContent = 'assign';
  headRow.appendChild(assignTh);
  thead.appendChild(headRow);
  table.appendChild(thead);

  var tbody = document.createElement('tbody');
  sorted.forEach(function(row) {
    var tr = document.createElement('tr');
    if (row.acknowledged) tr.style.opacity = '0.5';
    tr.addEventListener('click', function() { selectVictim(row.victim_id, true); });
    COLUMNS.forEach(function(col) {
      var td = document.createElement('td');
      var val = row[col[0]];
      td.textContent = val;
      if (col[0] === 'bpm_critical' || col[0] === 'battery_low') {
        td.className = val ? 'bool-true' : 'bool-false';
      }
      tr.appendChild(td);
    });
    var assignTd = document.createElement('td');
    var assignSpan = document.createElement('span');
    assignSpan.className = 'row-ack-btn' + (row.acknowledged ? ' acknowledged' : '');
    assignSpan.textContent = row.acknowledged ? '\u2713 Assigned' : 'Assign';
    assignSpan.addEventListener('click', function(e) {
      e.stopPropagation();
      toggleAcknowledge(row.db_id, row.acknowledged);
    });
    assignTd.appendChild(assignSpan);
    tr.appendChild(assignTd);
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  return table;
}

function buildFullSection(key, title, cssClass, rows, note, expanded, onToggle) {
  if (rows.length === 0) return null;

  var section = document.createElement('div');
  section.className = 'section ' + cssClass;

  var header = document.createElement('div');
  header.className = 'section-header';

  var titleSpan = document.createElement('span');
  titleSpan.textContent = title + ' (' + rows.length + ')';
  header.appendChild(titleSpan);

  var toggleSpan = document.createElement('span');
  toggleSpan.textContent = expanded ? 'HIDE' : 'SHOW';
  toggleSpan.style.fontSize = '10px';
  header.appendChild(toggleSpan);

  header.addEventListener('click', onToggle);
  section.appendChild(header);

  if (expanded) {
    if (note) {
      var noteEl = document.createElement('div');
      noteEl.className = 'section-note';
      noteEl.textContent = note;
      section.appendChild(noteEl);
    }
    section.appendChild(buildSectionTable(key, rows));
  }

  return section;
}

function buildTop5Column(containerEl, rows, emptyText) {
  containerEl.innerHTML = '';
  if (rows.length === 0) {
    var emptyDiv = document.createElement('div');
    emptyDiv.className = 'top5-empty';
    emptyDiv.textContent = emptyText;
    containerEl.appendChild(emptyDiv);
    return;
  }
  var top5 = rows.slice().sort(function(a, b) { return b.urgency_raw - a.urgency_raw; }).slice(0, 5);
  top5.forEach(function(r) {
    var row = document.createElement('div');
    row.className = 'top5-row' + (uiState.selectedVictimId === r.victim_id ? ' selected' : '');
    if (r.acknowledged) row.style.opacity = '0.5';
    var left = document.createElement('span');
    left.textContent = r.victim_id + (r.is_p1 ? ' \u26a0' : '');
    var right = document.createElement('span');
    right.textContent = r.urgency_score;
    row.appendChild(left);
    row.appendChild(right);
    row.addEventListener('click', function() { selectVictim(r.victim_id, true); });
    containerEl.appendChild(row);
  });
}

function buildSosSection(rows) {
  var sosRows = rows.filter(function(r) { return r.sos; });

  var section = document.createElement('div');
  section.id = 'sosSection';
  if (sosRows.length === 0) section.classList.add('sos-idle');

  var h2 = document.createElement('h2');
  h2.textContent = sosRows.length > 0 ? 'ACTIVE SOS - MANUAL DISTRESS SIGNAL' : 'MANUAL SOS';
  section.appendChild(h2);

  if (sosRows.length === 0) {
    var idleMsg = document.createElement('div');
    idleMsg.className = 'sos-idle-msg';
    idleMsg.textContent = 'No active SOS signals right now.';
    section.appendChild(idleMsg);
    return section;
  }

  var list = document.createElement('div');
  sosRows.forEach(function(r) {
    var span = document.createElement('span');
    span.className = 'sos-item';
    span.textContent = r.victim_id + ' - urgency ' + r.urgency_score;
    span.addEventListener('click', function() { selectVictim(r.victim_id, true); });
    list.appendChild(span);
  });
  section.appendChild(list);

  return section;
}

function updateDispatch(rows) {
  // Priority order: P1 (losing LoRa signal - act now while still reachable),
  // then active SOS, then remaining Critical Distress by urgency.
  var p1Rows = rows.filter(function(r) { return r.is_p1; }).sort(function(a, b) { return b.urgency_raw - a.urgency_raw; });
  var sosRows = rows.filter(function(r) { return r.sos && !r.is_p1; }).sort(function(a, b) { return b.urgency_raw - a.urgency_raw; });
  var criticalRest = rows.filter(function(r) { return r.bucket === 'critical' && !r.sos && !r.is_p1; })
    .sort(function(a, b) { return b.urgency_raw - a.urgency_raw; });
  var fullList = p1Rows.concat(sosRows).concat(criticalRest);

  var container = document.getElementById('dispatchList');
  var toggleContainer = document.getElementById('dispatchToggle');
  container.innerHTML = '';
  toggleContainer.innerHTML = '';

  if (fullList.length === 0) {
    var emptyDiv = document.createElement('div');
    emptyDiv.id = 'dispatchEmpty';
    emptyDiv.textContent = 'No critical or SOS victims right now - no dispatch needed.';
    container.appendChild(emptyDiv);
    return;
  }

  var visibleList = uiState.dispatchExpanded ? fullList : fullList.slice(0, 4);

  visibleList.forEach(function(r) {
    var i = fullList.indexOf(r);
    var teamLetter = String.fromCharCode(65 + i);
    var reason = r.is_p1 ? 'P1 - LOSING SIGNAL' : (r.sos ? 'MANUAL SOS' : ('urgency ' + r.urgency_score));
    var locPart = r.latitude !== '-' ? (' - ' + r.latitude + ', ' + r.longitude) : '';

    var row = document.createElement('div');
    row.className = 'dispatch-row';
    if (r.acknowledged) row.style.opacity = '0.5';

    var left = document.createElement('span');
    var teamSpan = document.createElement('span');
    teamSpan.className = 'dispatch-team';
    teamSpan.textContent = 'TEAM ' + teamLetter;
    left.appendChild(teamSpan);
    left.appendChild(document.createTextNode(' to dispatch to '));
    var targetSpan = document.createElement('span');
    targetSpan.className = 'dispatch-target';
    targetSpan.textContent = r.victim_id;
    left.appendChild(targetSpan);

    var right = document.createElement('span');
    right.textContent = reason + locPart;

    var assignSpan = document.createElement('span');
    assignSpan.className = 'row-ack-btn' + (r.acknowledged ? ' acknowledged' : '');
    assignSpan.textContent = r.acknowledged ? '\u2713' : 'Assign';
    assignSpan.addEventListener('click', function() { toggleAcknowledge(r.db_id, r.acknowledged); });

    row.appendChild(left);
    row.appendChild(right);
    row.appendChild(assignSpan);
    container.appendChild(row);
  });

  if (fullList.length > 4) {
    var link = document.createElement('span');
    link.className = 'show-more-link';
    link.textContent = uiState.dispatchExpanded ? 'Show less' : 'Show all ' + fullList.length + ' recommendations';
    link.addEventListener('click', function() {
      uiState.dispatchExpanded = !uiState.dispatchExpanded;
      render(latestRows);
    });
    toggleContainer.appendChild(link);
  }
}

function render(rows) {
  latestRows = rows;
  checkOperationStart(rows);
  var empty = document.getElementById('empty');
  var fullSectionsEl = document.getElementById('fullSections');
  fullSectionsEl.innerHTML = '';

  if (rows.length === 0) {
    empty.style.display = 'block';
    updateDispatch([]);
    buildTop5Column(document.getElementById('top5Critical'), [], 'None');
    buildTop5Column(document.getElementById('top5Warning'), [], 'None');
    updateDetailsPanel();
    return;
  }
  empty.style.display = 'none';

  updateDispatch(rows);
  updateMap(rows);
  updateDetailsPanel();

  var offline = rows.filter(function(r) { return r.bucket === 'offline'; });
  var critical = rows.filter(function(r) { return r.bucket === 'critical'; });
  var warning = rows.filter(function(r) { return r.bucket === 'warning'; });

  buildTop5Column(document.getElementById('top5Critical'), critical, 'No one critical right now');
  buildTop5Column(document.getElementById('top5Warning'), warning, 'No one in warning right now');

  var criticalSection = buildFullSection('critical', 'CRITICAL DISTRESS - FULL LIST', 'section-critical', critical, null,
    uiState.criticalExpanded, function() { uiState.criticalExpanded = !uiState.criticalExpanded; render(latestRows); });
  var warningSection = buildFullSection('warning', 'WARNING - FULL LIST', 'section-warning', warning, null,
    uiState.warningExpanded, function() { uiState.warningExpanded = !uiState.warningExpanded; render(latestRows); });
  var sosSection = buildSosSection(rows);
  var offlineSection = buildFullSection('offline', 'NO RECENT SIGNAL', 'section-offline', offline,
    'Wearables only transmit when critical or warning. Silence here means either the victim is stable and correctly not reporting, or the device is actually offline. Cannot be distinguished from telemetry alone.',
    true, function() {});

  if (criticalSection) fullSectionsEl.appendChild(criticalSection);
  if (warningSection) fullSectionsEl.appendChild(warningSection);
  if (sosSection) fullSectionsEl.appendChild(sosSection);
  if (offlineSection) fullSectionsEl.appendChild(offlineSection);
}

function fetchData() {
  fetch('/victims')
    .then(function(res) { return res.json(); })
    .then(function(victims) {
      var rows = victims.map(computeRow);
      document.getElementById('status').textContent =
        victims.length + ' victim(s) registered - last checked ' + new Date().toLocaleTimeString();
      render(rows);
    })
    .catch(function(e) {
      document.getElementById('status').textContent = 'Error loading data: ' + e;
    });
}

initMaps();
fetchData();
setInterval(fetchData, 3000);
</script>

</body>
</html>
"""


def _build_telemetry_out(reading, victim, previous_reading):
    depth_m = triage.compute_depth_m(reading.piezo_depth)
    previous_depth_m = (
        triage.compute_depth_m(previous_reading.piezo_depth) if previous_reading else None
    )

    hours_elapsed = None
    minutes_elapsed = None
    if previous_reading is not None:
        delta = reading.timestamp - previous_reading.timestamp
        hours_elapsed = delta.total_seconds() / 3600.0
        minutes_elapsed = delta.total_seconds() / 60.0

    rise_rate_m_per_hr = triage.compute_rise_rate_m_per_hr(depth_m, previous_depth_m, hours_elapsed)
    hours_to_critical_depth = triage.compute_hours_to_critical_depth(depth_m, rise_rate_m_per_hr)

    bpm_critical = triage.compute_bpm_critical(victim.age_years)
    bpm_norm_low = triage.compute_bpm_norm_low(victim.age_years)
    bpm_norm_high = triage.compute_bpm_norm_high(victim.age_years)
    age_vulnerability = triage.compute_age_vulnerability(victim.age_years)

    battery_drain_pct_per_min = triage.compute_battery_drain_pct_per_min(
        reading.battery_pct,
        previous_reading.battery_pct if previous_reading else None,
        minutes_elapsed,
    )

    dist_km = triage.compute_dist_km(reading.latitude, reading.longitude)

    urgency_score, covered_urgency_stop = triage.compute_urgency(
        bpm=reading.bpm,
        bpm_norm_low=bpm_norm_low,
        bpm_norm_high=bpm_norm_high,
        bpm_critical=bpm_critical,
        hours_to_critical_depth=hours_to_critical_depth,
        age_vulnerability=age_vulnerability,
        battery_drain_pct_per_min=battery_drain_pct_per_min,
    )

    pool_position = pool_zones.get_pool_position(reading.latitude, reading.longitude)

    return TelemetryOut(
        id=reading.id,
        victim_id=reading.victim_id,
        timestamp=reading.timestamp,
        latitude=reading.latitude,
        longitude=reading.longitude,
        bpm=reading.bpm,
        piezo_depth=reading.piezo_depth,
        depth_m=depth_m,
        rise_rate_m_per_hr=rise_rate_m_per_hr,
        bpm_critical=bpm_critical,
        hours_to_critical_depth=hours_to_critical_depth,
        urgency_score=urgency_score,
        covered_urgency_stop=covered_urgency_stop,
        dist_km=dist_km,
        age_years=victim.age_years,
        bpm_norm_low=bpm_norm_low,
        bpm_norm_high=bpm_norm_high,
        age_vulnerability=age_vulnerability,
        battery_pct=reading.battery_pct,
        battery_drain_pct_per_min=battery_drain_pct_per_min,
        sos=reading.sos,
        plr=reading.plr,
        zone_number=pool_position["zone_number"],
        pool_zone=pool_position["zone_string"],
        pool_x_norm=pool_position["x_norm"],
        pool_y_norm=pool_position["y_norm"],
    )


def _victim_with_latest(victim, db):
    rows = (
        db.query(Telemetry)
        .filter(Telemetry.victim_id == victim.id)
        .order_by(desc(Telemetry.timestamp))
        .limit(2)
        .all()
    )
    latest = _build_telemetry_out(rows[0], victim, rows[1] if len(rows) > 1 else None) if rows else None

    return VictimOut(
        id=victim.id,
        name=victim.name,
        device_id=victim.device_id,
        age_years=victim.age_years,
        acknowledged=victim.acknowledged,
        acknowledged_at=victim.acknowledged_at,
        latest_telemetry=latest,
    )