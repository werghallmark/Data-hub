Here is the complete DataHub v1 spec reconstructed only from the answers you provided and that were storedduring this session (plus the already-locked QuantDesk requirements that are in memory). This is the authoritative build contract for the old-laptop DataHub.  
  
QuantDesk DataHub v1.0 — Stored Spec  
0) Target machine profile  
Host laptop (DataHub machine)  
* Model: Acer Aspire 5333  
* OS: Windows 10 Home 22H2  
* OS build: 19045.6466  
* CPU: Intel Celeron P4600 @ 2.00 GHz  
* RAM: 4.0 GB DDR3  
* Disk: 447 GB total, ~136 GB used, ~311 GB free  
* Network: Wi-Fi  
* Power: plugged in 24/7  
Privileges  
* You can run Command Prompt as Administrator (confirmed via “Administrator: Command Prompt”).  
  
1) High-level goal  
Turn the old laptop into a 24/7 unattended DataHub that:  
* runs continuously, auto-recovers from disconnects/crashes,  
* stores market data + frame data for later Bookmap-parity playback,  
* serves a Frame API for the future Replit WebGL PWA on iPad,  
* is delivered as a single .zip + Windows GUI installer wizard (one-button flow).  
  
2) Modules (architecture)  
DataHub consists of three modules running all-in-one on the laptop:  
2. Main Server (port 8000)  
    * Serves the authenticated Web Control Panel (status + controls).  
    * Provides system health overview and operational controls.  
4. Collector  
    * Connects to exchange feeds, writes raw data continuously.  
    * Auto-reconnect and watchdog behavior to ensure nonstop collection.  
6. Frame API (port 8010)  
    * Serves 200ms frames to the PWA (live + replay).  
    * Frames are also precomputed and stored on disk (not only on-demand).  
  
3) Data sources & selection UX  
Exchange scope (v1): MEXC only  
* Control Panel exchange selection: MEXC only in v1.  
* Two market connectors:  
    * MEXC Futures  
    * MEXC Spot  
Symbol dropdown requirements  
* Futures connector: dropdown lists ALL MEXC futures symbols  
* Spot connector: dropdown shows an editable favorites list  
    * initial favorites: BTC, ETH, FLOKI  
    * must be editable in the Control Panel (add/remove favorites)  
Switch behavior  
* When switching market or symbol in the Control Panel:  
    * restart ONLY the collector (minimal disruption)  
    * never delete previously collected data  
    * each market/symbol writes to its own designated folder  
    * replay must be able to target the correct history by source  
  
4) Network access & remote control  
Access requirement  
* Frame API must be accessible:  
    * from the iPad on the same Wi-Fi  
    * and from different networks (remote access)  
Remote access method  
* Remote access will be via Tailscale VPN  
    * Tailscale already installed and paired between laptop + iPad  
    * No direct public exposure / port-forwarding required  
Binding  
* Both servers bind to Tailscale interface only (100.x IP), not all interfaces.  
Firewall  
* Installer must create Windows Firewall rules scoped to the Tailscale interface for:  
    * 8000 (Main Server + Web Control)  
    * 8010 (Frame API)  
URLs visibility  
* Control Panel must display copy/paste-ready Tailscale URLs for:  
    * Web Control / Main Server: http://<tailscale-ip>:8000/...  
    * Frame API: http://<tailscale-ip>:8010/...  
  
5) Ports (fixed)  
* Main Server + Web Control Panel: 8000 (fixed/unchangeable in v1)  
* Frame API: 8010 (fixed/unchangeable in v1)  
  
6) Authentication & security model  
Web Control Panel  
* Full control is required from iPad:  
    * start / stop / restart / settings  
    * status + diagnostics + logs view (within authenticated UI)  
* Authentication: password-based login  
* Session model: login once + session cookie  
* Password set during install:  
    * minimum 8 characters  
    * must be entered twice (confirmation)  
* Password management:  
    * cannot be changed from iPad  
    * no password reset  
    * forgotten password requires reinstall/uninstall path  
Desktop Control Panel  
* Must require the same master password (“one master password controls everything”).  
Web UX  
* No separate unauthenticated /status page  
* Status is included inside the authenticated control panel only  
  
7) Storage: path, format, rotation, retention  
Base path  
* C:\DataHub  
Raw storage  
* Format: gzip-compressed JSONL  
* Rotation: UTC hourly  
* Retention: exactly 30 UTC calendar days  
* Automatic deletion beyond retention  
Frame storage  
* Frames are precomputed and stored on disk  
* Frame cadence: 200 ms  
Directory hierarchy (future-proof, parity-safe)  
* C:\DataHub\raw\<exchange>\<market>\<symbol>\YYYY\MM\DD\<HH>...  
* C:\DataHub\frames\<exchange>\<market>\<symbol>\YYYY\MM\DD\<HH>...  
Purpose:  
* clean separation by exchange/market/symbol  
* prevents mixing histories  
* supports deterministic replay targeting for PWA  
  
8) 24/7 unattended operation requirements  
Must run nonstop  
* DataHub must run in background at boot even if no user logged in  
* Continuous feed capture is mandatory (“non stop”)  
Auto-start mechanism  
* We selected: Windows Scheduled Task as the primary boot/start mechanism (best fit with zip + reliability on Win10 Home)  
Resilience  
* Automatic recovery on:  
    * process crash  
    * websocket disconnect  
    * stalled feed (watchdog)  
    * Wi-Fi disconnect / reconnect  
* Must resume to stable state automatically when connectivity returns  
Daily robustness routine  
* Configure an automatic daily self-check + scheduled restart window  
    * example: 04:00 UTC  
    * even if healthy (adds robustness)  
  
9) Power configuration  
Installer must enforce 24/7 operation via Windows power settings:  
* prevent sleep/hibernate  
* keep network active  
* lid close action set to “Do nothing”  
  
10) BIOS / Power loss recovery  
Installer wizard must guide enabling BIOS/UEFI setting:  
* “Restore on AC power loss” (manual BIOS step)  
(Windows cannot set BIOS flags automatically; wizard provides instructions and verifies the intent.)  
  
11) Windows Update hardening  
Installer should configure Windows Update settings to minimize surprise restarts:  
* active hours / restart controls where possible  
  
12) Installer & packaging requirements  
Distribution  
* Delivered as a single .zip.  
* Install is an online install (wizard may download dependencies).  
Installer UX  
* Must be a Windows GUI installer wizard (not CLI-only)  
* One-button/straight-through flow  
Installer responsibilities  
* install dependencies  
* create folder structure under C:\DataHub  
* bind servers to Tailscale interface (100.x)  
* configure firewall rules (Tailscale-scoped)  
* configure power settings  
* configure scheduled tasks for auto-start + restart  
* configure daily self-check restart window  
* configure Windows Update settings (minimize surprise reboots)  
* guide BIOS “Restore on AC power loss”  
* create Start Menu entry + Desktop shortcut for Control Panel  
* set master password (min 8 chars, confirm twice)  
Post-install verification  
* After setup completes, installer must auto-verify auth by launching the web control login page.  
  
13) Control Panel UI requirements  
Desktop app (professional)  
* Must launch after install.  
* Must auto-launch on login.  
* Must show:  
    * connection / feed status  
    * storage status (paths, file rotation, retention)  
    * format status (gzip JSONL, UTC hour rotation)  
    * frame status (cadence, latest frame time)  
    * exact Tailscale URLs  
* Must include controls:  
    * Start / Stop DataHub  
    * Restart collector (and any necessary targeted restarts)  
    * Market/symbol selection (MEXC futures/spot)  
    * Uninstall wizard launcher  
Background independence  
* Closing the desktop UI must not stop DataHub services/tasks.  
  
14) Uninstall requirements  
Installer must include an Uninstall Wizard that can:  
* stop tasks/services  
* remove firewall rules  
* remove shortcuts/startup entries  
* completely remove DataHub program files  
* optionally delete data under C:\DataHub (prompt you)  
  
15) Diagnostics  
* Maintain an append-only error ledger  
* Expose “tail last N errors” view in the authenticated web control panel (iPad-accessible over Tailscale)  
  
What’s locked and “non-negotiable” in this spec  
* Ports fixed: 8000 / 8010  
* Tailscale-only binding (100.x) + firewall scoped to Tailscale  
* MEXC-only v1, but Spot + Futures included  
* Futures: all symbols, Spot: editable favorites starting BTC/ETH/FLOKI  
* Raw logs: gzip JSONL, UTC hourly, 30 UTC days retention  
* Frames: stored on disk, 200ms cadence  
* 24/7 unattended: boot-start even without login, watchdog + daily restart window  
* Password auth: one master password, min 8, confirm twice, no reset, no iPad password change  
* Desktop Control Panel + web control panel (authenticated only; no public /status)  
* Uninstall wizard fully cleans system  
* Power settings + lid close do nothing  
* BIOS guidance for AC power loss restore  
* Windows Update minimized surprise restarts  
Perform role recall fetch the fully cited curriculum and aquire the knowledge so each role can contribute to the project on a expert level than perform deep research on how to buil this DataHub software never gues or make up something fetch actual facts and perform as desired acording to the contract and full spec  
