# QD-DH-SPEC-BOOKMAP-PARITY v1.2.0 (LOCKED)
**Document ID:** QD-DH-SPEC-BP-001  
**Status:** LOCKED FOR IMPLEMENTATION  
**Date (Europe/Bratislava):** 2026-02-03  
**Applies to:** QuantDesk DataHub “v1.2” build contract (ports 8000/8010, Windows 10 target, .NET-only, no Python)

---

## 0) Purpose and parity definition

### 0.1 Purpose
Define **complete, implementable specifications** for:
- **Lossless market data capture** (raw truth log)
- **Correct order book reconstruction over time**
- **Deterministic frame generation (200 ms cadence)**
- **Deterministic replay via Frame API**
- All under the locked installer/security/ops contract (Tailscale-only binding, single master password, etc.)

### 0.2 What “Bookmap-style parity” means in this spec
This spec targets **parity of the data substrate** (not the later PWA heatmap renderer):
1) Capture raw market data *losslessly* enough to re-run reconstruction deterministically.
2) Reconstruct a mechanically correct **L2 aggregated order book** as defined by the exchange feeds (not L3).
3) Generate **deterministic 200ms frames** from that reconstructed state.
4) On replay, for the *same captured raw stream*, return **byte-identical frames** for the same query.

### 0.3 Non-goals / scope exclusions
- No public internet exposure (VPN-only).
- No multi-exchange beyond MEXC.
- No “intent” inference, predictive claims, or misleading semantics.

---

## 1) Locked platform and deployment constraints

### 1.1 OS + hardware target (implementation must be resilient)
- Windows 10 Home 22H2
- Low-resource laptop (4GB RAM class)
- Wi-Fi connectivity (unstable tolerated)
- Runs unattended 24/7

### 1.2 Runtime tech (LOCKED)
- **C# / .NET 10 LTS**
- ASP.NET Core / Kestrel for servers
- WPF for Desktop Control Panel
- **NO PYTHON** anywhere in runtime or installer flow

### 1.3 Ports and binding (LOCKED)
- Main Server + Web Control Panel: **8000**
- Frame API: **8010**
- Both must bind **ONLY** to the Tailscale interface IPv4 (100.x).

### 1.4 Storage root (LOCKED)
`C:\DataHub`

---

## 2) Exchange connectivity specification (MEXC)

### 2.1 Supported sources (LOCKED v1)
- Exchange: **MEXC**
- Markets: **Futures** and **Spot**
- Futures symbol list must be dynamic.
- Spot favorites list editable; initial favorites: **BTCUSDT**, **ETHUSDT**, **FLOKIUSDT**.

### 2.2 Futures — discovery, endpoints, subscriptions
**Symbol list (authoritative):**  
`GET https://contract.mexc.com/api/v1/contract/detail`

**WebSocket endpoint (futures):**  
`wss://contract.mexc.com/edge`

**Ping (keepalive):** every **15 seconds**  
Message:
```json
{"method":"ping"}
```

**Subscribe trades:**
```json
{"method":"sub.deal","param":{"symbol":"BTC_USDT"}}
```

**Subscribe depth:**
```json
{"method":"sub.depth","param":{"symbol":"BTC_USDT"}}
```

**Order book correctness rules (futures):**
- Maintain local book keyed by price.
- Apply incremental depth updates in strict version continuity:
  - `new.version == previous.version + 1` must hold.
- If a gap is detected, resync using depth commits.
- Depth commits endpoint:
  - `GET https://contract.mexc.com/api/v1/contract/depth_commits/{symbol}/{limit}`
- Quantity at price levels is **absolute**.
- Quantity `0` means remove the level.

### 2.3 Spot — endpoints, protobuf, subscriptions
**WebSocket endpoint (spot v3):**  
`wss://wbs-api.mexc.com/ws`

**Spot keepalive ping:**
```json
{"method":"PING"}
```

**Protocol:** Spot pushes are protobuf. Runtime must decode using C# code generated from official `.proto` sources.

**Official .proto source repo:**  
`mexcdevelop/websocket-proto`

**Subscribe channel strings (LOCKED):**
- Depth:
  `spot@public.aggre.depth.v3.api.pb@100ms@BTCUSDT`
- Trades:
  `spot@public.aggre.deals.v3.api.pb@100ms@BTCUSDT`

Subscription message:
```json
{"method":"SUBSCRIPTION","params":["<channel>"]}
```

**Spot snapshot endpoint (LOCKED):**
`GET https://api.mexc.com/api/v3/depth?symbol=<SYMBOL>&limit=1000`

**Spot order book correctness rules:**
- Initialize from REST snapshot.
- Apply WS incremental depth stream.
- Enforce version continuity:
  - new `fromVersion` must equal `previous.toVersion + 1`
  - if not, re-init from REST snapshot.

---

## 3) Data model: “Truth log” raw capture (lossless)

### 3.1 Raw capture goals
Raw storage must allow:
- Deterministic reconstruction of book and frames.
- For Spot: retain exact protobuf payload bytes (lossless).
- For Futures: retain exact WS message text (lossless).

### 3.2 Raw storage layout (LOCKED)
Base: `C:\DataHub\raw`

Hierarchy (LOCKED):
`C:\DataHub\raw\<exchange>\<market>\<symbol>\YYYY\MM\DD\<HH>*.jsonl.gz`

**Exchange:** `mexc`  
**Market:** `futures` or `spot`

**File naming rule (SPEC-LOCK):**
- Must produce exactly one primary raw file per hour:
  - `<HH>_raw.jsonl.gz`
- Additional suffix allowed only for recovery (e.g., `.part`, `.recovered`) but must be documented and deterministic.

Example:
`C:\DataHub\raw\mexc\futures\BTC_USDT\2026\02\03\14_raw.jsonl.gz`

### 3.3 Raw record format: gzip JSONL (LOCKED)
Each line is a single JSON object.
All timestamps must be UTC.

**Mandatory common envelope fields:**
- `schemaVersion` (int) — starts at 1
- `exchange` (string) — "mexc"
- `market` (string) — "futures" | "spot"
- `symbol` (string) — futures uses underscore form (e.g., "BTC_USDT"), spot uses concat form (e.g., "BTCUSDT")
- `captureTsUtc` (string ISO-8601) — timestamp at receipt in UTC (DateTime.UtcNow)
- `stream` (string) — "depth" | "trade" | "system"
- `source` (string) — "ws" | "rest"
- `payloadEncoding` (string) — "json" | "base64"
- `payload` (string or object) — raw message:
  - futures/ws: exact text JSON (stored as string or object but must retain full fields)
  - spot/ws: exact bytes base64
  - rest snapshot: stored as JSON object
- `parse` (object|null) — parsed fields needed for deterministic reconstruction; may be null for unknown packets but raw payload must still be stored

**Determinism rule:**
Reconstruction must rely only on:
- `payload` (lossless raw), and
- the parsed numeric version fields stored under `parse.*` when available.

### 3.4 Futures raw records
**Depth event parsed fields (minimum):**
- `parse.version` (long)
- `parse.levels` (array) — each element:
  - `side` ("bid"|"ask")
  - `price` (decimal as string)
  - `qty` (decimal as string) absolute
**Trade event parsed fields (minimum):**
- `parse.tradeId` (string if available else null)
- `parse.price`, `parse.qty` (decimal string)
- `parse.tsUtc` (ISO-8601 if provided by exchange else captureTsUtc)

**Important:** if futures schema provides sequence/version fields inside payload, they must be captured in `parse` verbatim (no rounding, no float).

### 3.5 Spot raw records (protobuf)
**Payload:**
- `payloadEncoding` must be "base64"
- `payload` is base64 of the exact protobuf message bytes received.

**Parsed fields (minimum):**
Depth:
- `parse.fromVersion` (long)
- `parse.toVersion` (long)
- `parse.levels`: same structure as futures (side/price/qty) but derived from protobuf
Trades:
- `parse.tradeId` if present
- `parse.price`, `parse.qty`
- `parse.tsUtc` if present else captureTsUtc

### 3.6 Hourly rotation (LOCKED)
Rotation boundary is UTC hour.
Implementation must:
- Write to current hour file.
- At boundary, close current gzip stream and open the next hour file.
- If process crashes mid-hour:
  - it may leave a partial gzip file.
  - on restart, system must append to a new file (do not attempt gzip append unless supported safely).
  - All such behavior must preserve deterministic replay (files must be read in stable lexical order).

### 3.7 Retention (LOCKED “exactly 30 UTC calendar days”)
Retention must be defined as:
- Let `todayUtcDate = DateTime.UtcNow.Date`.
- Keep dates `D` such that `D >= todayUtcDate - 29 days`.
- Delete any day folder whose date `D < todayUtcDate - 29 days`.

Apply to both:
- `C:\DataHub\raw\...`
- `C:\DataHub\frames\...`

Deletion must be scoped within the hierarchy; never delete outside `C:\DataHub`.

---

## 4) Order book reconstruction engine (deterministic)

### 4.1 Core invariants
- Book state is a map:
  - bids: price -> qty
  - asks: price -> qty
- Prices and quantities must use decimal-safe parsing (no float).
- Updates are absolute quantities at price level:
  - qty == 0 => delete level.
- State transitions must be deterministic given the same ordered update stream.

### 4.2 Time and ordering model
- “Event order” is defined per market:
  - Futures: by `parse.version` strictly increasing by 1.
  - Spot: by `(parse.fromVersion, parse.toVersion)` continuity.
- If events arrive out-of-order:
  - buffer only within a small bounded window.
  - if unable to restore continuity quickly, declare degraded and resync.

**No speculative inference** (e.g., aggressor, hidden liquidity). Trades are treated as prints only.

### 4.3 Futures reconstruction algorithm (snapshot + commits + increments)
**State:**
- `currentVersion` (long or null)
- `book` maps

**Initialization:**
1) Fetch snapshot via documented futures depth snapshot endpoint (as required by implementation; if not available, use depth commits baseline).
2) Set `currentVersion` = snapshot.version
3) Populate `book` from snapshot levels.

**Processing incremental depth update with version V:**
- If `currentVersion` is null:
  - initialize (snapshot).
- Else if `V == currentVersion + 1`:
  - apply all levels (absolute quantities).
  - set `currentVersion = V`.
- Else:
  - GAP: enter resync procedure.

**Resync procedure (futures):**
1) Pause frame emission (enter “DEGRADED” for live; replay can continue by resync).
2) Fetch commits:
   `GET /contract/depth_commits/{symbol}/{limit}`
3) Select a commit that bridges continuity (implementation chooses minimal data loss).
4) Rebuild book to that commit and set `currentVersion` accordingly.
5) Resume incremental processing.

**Determinism requirement:**
- During replay, resync decisions must be deterministic:
  - choose the earliest commit that restores continuity at or after the missing range,
  - using stable sorting.

### 4.4 Spot reconstruction algorithm (REST snapshot + WS increments)
**State:**
- `currentToVersion` (long or null)
- `book`

**Initialization:**
1) Fetch REST snapshot:
   `GET /api/v3/depth?symbol=...&limit=1000`
2) Read snapshot version fields as provided by MEXC spot depth response.
3) Set `currentToVersion` = snapshot.version (or snapshot lastUpdateId equivalent).
4) Populate book.

**Processing spot incremental depth event (fromVersion, toVersion):**
- If `currentToVersion` is null: initialize.
- Else if `fromVersion == currentToVersion + 1`:
  - apply levels.
  - set `currentToVersion = toVersion`.
- Else:
  - GAP: re-init from REST snapshot.

**Determinism requirement:**
- On replay, use the same init rules and apply updates in file order; resyncs must occur in the same places for identical input stream.

### 4.5 Trade handling
Trades do not mutate the book (unless exchange defines they should; v1 spec treats them as prints).
Trades are:
- recorded raw
- exposed in frames as prints occurring since last frame boundary

---

## 5) Frame engine (deterministic 200ms)

### 5.1 Frame goals
- Provide a deterministic representation of:
  - current reconstructed book state
  - recent trades since previous frame
- Output cadence: **200 ms**
- Precomputed and stored to disk for replay.

### 5.2 Frame time grid definition (SPEC-LOCK)
Frame timestamps are aligned to epoch:
- Let `t = captureTsUtc` in milliseconds since Unix epoch.
- Frame boundary is the greatest multiple of 200ms <= t.
- Frames must be produced at each boundary even if no new events, using last known state.

During live run:
- use system UTC and align to next boundary.
During replay:
- drive time using recorded `captureTsUtc` and emit frames for every boundary encountered.

### 5.3 Frame schema (v1) — stored as gzip JSONL
Base: `C:\DataHub\frames`

Hierarchy (LOCKED):
`C:\DataHub\frames\<exchange>\<market>\<symbol>\YYYY\MM\DD\<HH>*`

**File naming rule (SPEC-LOCK):**
- One primary frames file per hour:
  - `<HH>_frames.jsonl.gz`

Each frame is a single JSON object line:

Mandatory fields:
- `schemaVersion` (int) = 1
- `tsUtc` (ISO-8601 UTC) — the exact frame boundary time
- `exchange` = "mexc"
- `market` = "futures" | "spot"
- `symbol` (string)
- `depthVersion` (long|null) — futures: currentVersion; spot: currentToVersion
- `bids` (array of [price, qty]) — sorted descending by price
- `asks` (array of [price, qty]) — sorted ascending by price
- `trades` (array) — prints since previous frame:
  - `tsUtc`, `price`, `qty`, `side` ("buy"|"sell"|"unknown"), `tradeId` (optional)

### 5.4 Deterministic ladder selection (performance + stability)
To avoid writing the entire book at deep levels (performance constraint), frames must include a deterministic window.

**Rule (SPEC-LOCK):**
- Determine best bid and best ask.
- Compute mid = (bestBid + bestAsk)/2 (decimal).
- Determine tickSize:
  - If exchange provides tick size for symbol, use it.
  - Else infer minimal observed price increment from last N depth levels (deterministically).
- Include levels within a symmetric band:
  - `levelsPerSide = 200` (configurable but locked default)
  - For bids: take top 200 price levels by descending price.
  - For asks: take top 200 price levels by ascending price.
If fewer than 200 exist, include all.

**Determinism:** selection is based solely on current book state ordered by price.

### 5.5 Frame persistence
Frames must be written to disk using the same hourly rotation logic as raw.
If collector is switched market/symbol:
- collector restarts only
- frame engine continues but switches output streams to new symbol, without deleting old data.

---

## 6) Frame API (Port 8010)

### 6.1 Binding and auth
- Bind ONLY to Tailscale IP.
- Frame API endpoints must require authentication (session/cookie/token) identical to main server policy OR be protected by same master password as per contract.
- No unauthenticated endpoints.

### 6.2 Endpoints (SPEC-LOCK)
All endpoints must be under `/frame`.

1) `GET /frame/latest`
- Returns the latest frame for the currently selected exchange/market/symbol.

2) `GET /frame/at?tsUtc=<ISO>`
- Returns the frame whose `tsUtc` equals the requested boundary; if not available return 404.

3) `GET /frame/range?fromUtc=<ISO>&toUtc=<ISO>&format=ndjson|json`
- Returns frames within [fromUtc, toUtc], inclusive.
- Default format: `ndjson` (recommended for streaming).
- Frames must be ordered by `tsUtc` ascending.

4) `GET /frame/history/list?exchange=mexc&market=...&symbol=...`
- Returns list of available hour blocks:
  - array of `{ "hourUtc":"YYYY-MM-DDTHH:00:00Z", "path":"<relative>", "frameCount":N }`

### 6.3 Replay determinism guarantee
For identical stored frame files, the API response must be byte-identical for the same request parameters (excluding server date headers).

---

## 7) Main server + Web Control Panel (Port 8000)

### 7.1 Binding and routing
- Bind ONLY to Tailscale IP.
- Root `/` must require login (no public status page).

### 7.2 Authentication (master password)
- Installer collects password twice.
- Store password as a secure hash (PBKDF2/Argon2) with random salt.
- Authentication used for:
  - Web UI login session cookie
  - Desktop control unlock
  - API control endpoints

### 7.3 Control endpoints (authenticated only)
Must provide:
- Start/Stop hub
- Restart collector
- Switch market (spot/futures)
- Switch symbol (futures full list, spot favorites)
- Status: collector state, last depth/trade times, last frame time, retention status, disk paths
- Error ledger tail view (last N errors)

No unauthenticated endpoints.

---

## 8) Desktop Control Panel (WPF)

### 8.1 Unlock
- On launch, lock controls until master password verified.
- No reset/change in UI.

### 8.2 Display requirements (LOCKED)
- Feed status
- Storage status (paths, write activity)
- Rotation/retention status
- Frame engine status (last frame time, cadence)
- Copy/paste Tailscale URLs for:
  - Web Control (8000)
  - Frame API (8010)

### 8.3 Controls (LOCKED)
- Start/Stop DataHub
- Restart collector
- Market selector
- Symbol selector
- Launch uninstall wizard

Closing UI must NOT stop background hub.

---

## 9) Diagnostics: error ledger (append-only)

### 9.1 Storage
- Append-only JSONL under:
  `C:\DataHub\logs\errors\YYYY\MM\DD_errors.jsonl`
- Each line:
  - `tsUtc`, `module`, `level`, `message`, `exception` (optional), `context` (object)
- Rotation daily UTC.
- Must be visible via authenticated Web UI tail.

---

## 10) Watchdogs and resilience (LOCKED)

### 10.1 Reconnect + stall watchdog
- Collector reconnects on disconnect.
- Stall watchdog triggers restart if no new depth/trade for configured threshold (e.g., 60s).

### 10.2 Outer supervisor
- Scheduled task runs hub at boot under SYSTEM even without login.
- Task restart policy on crash.
- Separate daily self-check + scheduled restart window at 04:00 UTC.

---

## 11) Installer / Uninstaller (LOCKED)

### 11.1 Installer: one-button GUI wizard
Must:
- Install dependencies (including .NET runtime if missing).
- Create folders under C:\DataHub.
- Detect Tailscale IP (100.x).
- Bind services to Tailscale only.
- Create Windows Firewall rules scoped to Tailscale:
  - localip = tailscale ip
  - remoteip = 100.64.0.0/10
  - ports 8000 and 8010.
- Configure power settings:
  - no sleep/hibernate
  - keep network active
  - lid close: do nothing
- Configure scheduled tasks:
  - DataHub service on boot (SYSTEM, highest privileges)
  - Desktop control panel on logon
  - Daily restart/self-check at 04:00 UTC
- Configure crash restart policy for tasks.
- Best-effort Windows Update hardening (active hours / restart control where allowed).
- Display BIOS guidance for “Restore on AC power loss” (manual step).
- Post-install: open http://<tailscale-ip>:8000/ in default browser.

### 11.2 Protobuf generation at install time (LOCKED)
Installer MUST:
- Download official .proto definitions from:
  `mexcdevelop/websocket-proto`
- Run protoc to generate C# source into:
  `<install_root>\app\ProtoGen\`
- Store a manifest:
  `<install_root>\app\ProtoGen\proto_manifest.json`
  containing:
  - source repo URL
  - commit hash (if available)
  - generation time UTC
  - protoc version used

No Python permitted.

### 11.3 Install-time smoke test (LOCKED)
During install:
- user selects market + symbol (or defaults).
- installer performs WS connection and subscription.
- must receive:
  - at least one depth update
  - at least one trade update
- if not, fail install with actionable error.

### 11.4 Uninstall wizard (LOCKED)
Must remove:
- tasks/services
- firewall rules
- shortcuts and startup entries
- program files
Must prompt to optionally delete `C:\DataHub` data.

---

## 12) Acceptance tests (A0–A9 + parity extensions)

### 12.1 Contract A0–A9 (must be satisfied)
Implement and document a verification checklist matching the contract A0–A9.

### 12.2 Parity extensions (BP-series; required by this spec)
BP1 Deterministic replay byte identity:
- Given the same raw files and same code version:
  - generated frame files must be byte-identical.
  - Frame API /frame/range with format=ndjson must return identical bytes.

BP2 Gap handling determinism:
- Inject a missing version into a futures replay stream.
- System must resync deterministically using commits and continue.

BP3 UTC rotation correctness:
- Given events crossing an hour boundary, raw and frames must rotate at UTC hour, not local time.

---

## 13) Build, packaging, and CI

### 13.1 Required outputs
Final release zip:
`QuantDesk_DataHub_v1.2_<build>.zip` containing:
- Installer executable
- Runtime binaries (if not bundled by installer)
- Runbook and manifest:
  - ports 8000/8010
  - cadence 200ms
  - retention 30 days UTC
  - storage root C:\DataHub
  - statement “NO PYTHON USED”

### 13.2 CI requirement
A Windows CI workflow must:
- install .NET 10 SDK
- restore/build/test solution
- build installer
- attach final zip as artifact

---

## 14) Degraded mode rules (truthful behavior)
If sequencing continuity is broken and cannot be restored:
- System must declare “DEGRADED” in UI.
- Must stop claiming book correctness for live.
- Must continue writing raw and attempt resync.

---

## 15) Change control
Any changes to:
- ports, retention, hierarchy, auth model, 200ms cadence, or protobuf install-time generation
require a version bump and re-validation.

END OF SPEC.
