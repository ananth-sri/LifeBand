# Triton Lifeband Backend

A small FastAPI backend that sits between your ESP32 devices and the Flutter app.
ESP32 devices POST telemetry readings in; the Flutter app GETs them back out.

## Setup

```bash
cd triton_backend
python3 -m venv venv
source venv/bin/activate        # on Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Run it

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- `--host 0.0.0.0` is important — it makes the server reachable from other devices
  on your network (your phone, your ESP32), not just `localhost`.
- Interactive API docs: open `http://<your-computer-ip>:8000/docs` in a browser.
  You can test every endpoint from there without writing any code.

To find your computer's local IP (needed by the phone and ESP32 to reach this server):
```bash
# macOS
ipconfig getifaddr en0
```

## Database

Uses SQLite by default (`triton.db`, created automatically in this folder on first run).
Zero setup needed for local development/testing.

**To switch to Postgres or MySQL later:** edit `DATABASE_URL` in `database.py`.
See the comments in that file for the connection string format. You'll also need to
`pip install psycopg2-binary` (Postgres) or `pip install pymysql` (MySQL).

## API Overview

| Method | Endpoint                          | Purpose                                   |
|--------|------------------------------------|--------------------------------------------|
| POST   | `/victims`                        | Register a new victim/ESP32 device        |
| GET    | `/victims`                        | List all victims + their latest reading   |
| GET    | `/victims/{id}`                   | Get one victim + their latest reading     |
| POST   | `/telemetry`                      | ESP32 pushes a new sensor reading         |
| GET    | `/victims/{id}/telemetry`         | Full reading history for one victim       |

## Testing without hardware

1. Register a test victim:
   ```bash
   curl -X POST http://localhost:8000/victims \
     -H "Content-Type: application/json" \
     -d '{"name": "Test Victim", "device_id": "esp32-001"}'
   ```

2. Push a fake reading:
   ```bash
   curl -X POST http://localhost:8000/telemetry \
     -H "Content-Type: application/json" \
     -d '{"device_id": "esp32-001", "bpm": 78, "piezo_depth": 1200, "latitude": 30.2672, "longitude": -97.7431}'
   ```

3. Check the dashboard list:
   ```bash
   curl http://localhost:8000/victims
   ```

## ESP32 integration notes

Your ESP32 firmware needs to make an HTTP POST to `/telemetry` with a JSON body.
Using the Arduino `HTTPClient` library, roughly:

```cpp
HTTPClient http;
http.begin("http://<your-computer-ip>:8000/telemetry");
http.addHeader("Content-Type", "application/json");

String payload = "{\"device_id\":\"esp32-001\",\"bpm\":" + String(bpm) +
                  ",\"piezo_depth\":" + String(piezoDepth) +
                  ",\"latitude\":" + String(lat, 6) +
                  ",\"longitude\":" + String(lon, 6) + "}";

int responseCode = http.POST(payload);
http.end();
```

Each ESP32 needs a unique `device_id` that matches what you registered via `/victims`.
