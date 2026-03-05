# Spec: Replace HTTP Polling with Convex WebSocket Subscriptions

**Priority:** High (cost reduction + latency improvement)
**Estimated Effort:** 2–3 days
**Status:** Implemented

---

## Problem Statement

The app currently simulates real-time sync by **polling** Convex via HTTP POST requests to `/api/query` on a timer loop. Convex natively supports **real-time WebSocket subscriptions** where the server pushes updates to the client automatically — but the current codebase never uses this capability. Instead, it re-queries every N seconds, which:

1. **Burns through the free-tier function call quota** (1M/month) — every poll is a billed function call
2. **Adds 0–3 seconds of latency** (you wait for the next poll cycle to detect changes)
3. **Wastes bandwidth & battery** with identical repeated responses when nothing changed
4. **Requires a watchdog timer** to detect stale connections — a symptom of the polling approach

### Current Polling Surfaces

| Location | File | What it polls | Interval | Notes |
|---|---|---|---|---|
| Clipboard listener (Mac) | `mac/OTPSync/ClipboardManager.swift` L207–215 | `clipboard:getLatest` | 3s | Main clipboard sync loop |
| Pairing listener (Mac) | `mac/OTPSync/PairingManager.swift` L43–52 | `pairings:watchForPairing` | 1s | QR pairing handshake |
| Unpair monitor (Mac) | `mac/OTPSync/PairingManager.swift` L101–109 | `pairings:exists` | 30s | Detects remote unpair |
| Polling engine (Mac) | `mac/OTPSync/ConvexManager.swift` L307–350 | Generic `subscribe()` | configurable | The `subscribe<T>()` method IS the polling loop |
| Clipboard listener (Android) | `ClipboardAccessibilityService.kt` L350–400 | `clipboard:getLatest` via `getLatestClipboard()` | 3s | Background service polling |
| Clipboard listener (Android) | `Homescreen.kt` L200–213 | `listenToClipboard()` → `subscribeToClipboard()` | 3s | UI Flow-based polling |
| Polling engine (Android) | `ConvexManager.kt` L374–410 | `subscribeToClipboard()` | 3s | The Flow-based polling loop |

### Why Convex Doesn't Need Polling

Convex queries are **reactive by default**. When you subscribe to a query via the Convex client SDK (using the WebSocket sync protocol), the server:
- Evaluates the query once
- Keeps the WebSocket connection open
- Automatically re-evaluates and pushes a new result **only** when the underlying data changes

This means zero wasted calls, sub-100ms latency on updates, and no need for watchdog timers.

---

## Solution

Replace the custom HTTP-POST-based `ConvexManager` with the official Convex client SDKs, which handle WebSocket subscriptions natively.

### Phase 1: Mac (Swift) — Replace `ConvexManager.swift`

**Current:** Custom `ConvexManager` class uses `URLSession` HTTP POST to `/api/query` and `/api/mutation`. The `subscribe()` method is a `Timer`-based polling loop.

**Target:** Use the [convex-swift](https://github.com/nicholasgasior/convex-swift) community client, OR implement the Convex sync protocol directly over WebSocket. If neither is viable, use the Convex HTTP Streaming API (`/api/query` with `Accept: text/event-stream`) as a middle ground.

#### Option A: Convex HTTP Streaming (Recommended — Lowest Risk)

Convex supports Server-Sent Events (SSE) on query endpoints. This gives push-based updates over HTTP without needing a full WebSocket client SDK.

**Changes required:**

1. **`ConvexManager.swift`** — Add a new `subscribeSSE()` method:
   - Make a GET/POST request to the Convex query endpoint with `Accept: text/event-stream`
   - Parse the SSE stream using `URLSession`'s async bytes API
   - Emit values via a Combine `PassthroughSubject` (replacing the polling `CurrentValueSubject`)
   - Handle reconnection on stream drop

2. **`ConvexManager.swift`** — Remove or deprecate the `subscribe<T>()` polling method (lines 307–350)

3. **`ClipboardManager.swift`** — Update `listenForAndroidClipboard()` (line 207):
   - Replace `ConvexManager.shared.subscribe(to:args:interval:type:)` call with the new SSE-based method
   - Remove the `interval: 3.0` parameter (no longer needed)
   - Remove the watchdog timer (`startListenerWatchdog()` / lines 298–316) — SSE reconnection handles this

4. **`PairingManager.swift`** — Update `startConvexPairingListener()` (line 43):
   - Replace polling subscribe with SSE subscribe
   - Remove `interval: 1.0`

5. **`PairingManager.swift`** — Update `startMonitoringPairingStatus()` (line 101):
   - Replace polling subscribe with SSE subscribe
   - Remove `interval: 30.0`

#### Option B: WebSocket Sync Protocol (Higher Effort, Best Result)

Implement the [Convex sync protocol](https://docs.convex.dev/api/sync-protocol) over a raw WebSocket connection. This is what the official JS/Python/Rust clients do.

Only pursue this if Option A proves insufficient (e.g., SSE not supported for the endpoint version you're on).

### Phase 2: Android (Kotlin) — Replace Polling in `ConvexManager.kt`

**Current:** `subscribeToClipboard()` is a Kotlin `Flow` with `delay(3000)` polling loop. `getLatestClipboard()` is used by the accessibility service with its own `delay(3000)` loop.

**Target:** Same approach as Mac — use Convex HTTP Streaming or the official Convex client.

#### Option A: HTTP Streaming (SSE) in Kotlin (Recommended)

**Changes required:**

1. **`ConvexManager.kt`** — Add `subscribeSSE()` method:
   - Use `OkHttp` or `HttpURLConnection` with streaming response
   - Parse SSE events (`data:` lines)
   - Emit via Kotlin `Flow` using `callbackFlow` or `channelFlow`
   - Handle reconnection with exponential backoff

2. **`ConvexManager.kt`** — Remove `subscribeToClipboard()` polling Flow (lines 374–410)

3. **`ClipboardAccessibilityService.kt`** — Update `startConvexPolling()` (line 348):
   - Replace the `while(isActive) { delay(3000) }` polling loop with SSE flow collection
   - Remove manual `delay()` calls

4. **`Homescreen.kt`** — Update `LaunchedEffect` (line 200):
   - Use the new SSE-based flow from `ConvexManager`

#### Option B: Official Convex Kotlin/Java SDK

Check if an official or community Convex SDK exists for Kotlin/Android. If so, prefer it over hand-rolling SSE.

### Phase 3: Convex Backend (No Changes Expected)

The Convex functions (`clipboard:getLatest`, `pairings:watchForPairing`, `pairings:exists`) are already defined as `query` functions. Convex `query` functions are automatically reactive — they work with both HTTP polling AND WebSocket/SSE subscriptions with zero changes needed.

**No backend changes required.**

---

## Implementation Notes

### What NOT to Touch

- **Local clipboard monitoring** (`ClipboardManager.swift` lines 55–79) — The `DispatchSourceTimer` that polls `NSPasteboard.changeCount` every 300ms is **correct and necessary**. macOS does not provide push notifications for clipboard changes. This is local-only and does not hit Convex.

- **The upload path** (`clipboard:send` mutations) — These are one-shot mutations, not subscriptions. They remain as HTTP POST calls.

### SSE Implementation Reference

Convex SSE format (verify against current Convex docs):

```
POST /api/query
Content-Type: application/json
Accept: text/event-stream

{"path": "clipboard:getLatest", "args": {"pairingId": "..."}, "format": "json"}
```

Response stream:
```
data: {"status": "success", "value": {...}}

data: {"status": "success", "value": {...}}
```

Each `data:` line is a new result pushed when the underlying data changes.

### Reconnection Strategy

- On stream drop: reconnect with exponential backoff (1s, 2s, 4s, max 30s)
- On app foregrounding (Mac: `NSWorkspace.didWakeNotification`; Android: `onResume`): force reconnect
- Track `isConnected` state for UI indicators

### Watchdog Removal

Once SSE/WebSocket is in place, remove:
- `ClipboardManager.swift`: `watchdogTimer`, `startListenerWatchdog()`, `lastListenerUpdate`
- `ClipboardAccessibilityService.kt`: the outer `while(isActive)` polling loop

### Migration Path

1. Implement the new SSE `subscribe` method alongside the existing polling one
2. Switch one surface at a time (clipboard first, then pairing, then unpair monitor)
3. Validate each surface works before removing the old polling code
4. Remove the old `subscribe<T>(to:args:interval:type:)` method and watchdog last

---

## Files to Modify

| File | Action |
|---|---|
| `mac/OTPSync/ConvexManager.swift` | Add SSE subscribe method; deprecate/remove polling `subscribe()` |
| `mac/OTPSync/ClipboardManager.swift` | Use new subscribe; remove watchdog timer |
| `mac/OTPSync/PairingManager.swift` | Use new subscribe for pairing + unpair monitoring |
| `android/.../ConvexManager.kt` | Add SSE subscribe Flow; remove polling `subscribeToClipboard()` |
| `android/.../ClipboardAccessibilityService.kt` | Replace polling loop with SSE flow |
| `android/.../Homescreen.kt` | Update `LaunchedEffect` to use SSE flow |

---

## Acceptance Criteria

- [ ] No timer-based polling of Convex query endpoints remains in the codebase
- [ ] Clipboard sync latency is < 1 second (down from up to 3s)
- [ ] App reconnects automatically after network interruption
- [ ] Convex dashboard shows dramatically fewer function calls at idle (near zero when no clipboard activity)
- [ ] Local clipboard monitoring (macOS `NSPasteboard.changeCount` polling) is untouched
- [ ] All existing functionality works: copy Mac→Android, copy Android→Mac, pairing, unpairing

---

## Manual Testing Instructions

### Prerequisites
- A paired Mac + Android setup
- Convex dashboard open at https://dashboard.convex.dev (to monitor function call volume)
- Both apps running

### Test 1: Clipboard Sync Latency (Mac → Android)

1. Open the Convex dashboard → Functions tab to watch call counts
2. On Mac, copy any text (e.g. "test-mac-123")
3. **Expected:** Text appears on Android clipboard within ~1 second (previously up to 3s)
4. Verify in Convex dashboard that no repeated `clipboard:getLatest` calls are firing — you should see the query subscription active but not re-executing unless data changes

### Test 2: Clipboard Sync Latency (Android → Mac)

1. On Android, copy any text (e.g. "test-android-456")
2. **Expected:** Text appears on Mac clipboard within ~1 second
3. Check Mac console logs — you should NOT see periodic "polling" log messages

### Test 3: Idle Function Call Consumption

1. With both apps paired and idle (no clipboard activity), wait 5 minutes
2. Check the Convex dashboard function call count
3. **Expected:** Near-zero function calls during idle period. Previously, the app would make ~100 calls/min at idle (3s interval × 2 devices = ~40/min, plus pairing monitors)

### Test 4: Network Interruption Recovery

1. Copy text successfully (verify sync works)
2. Disable Wi-Fi on the Mac for 10 seconds
3. Re-enable Wi-Fi
4. Copy new text on Android
5. **Expected:** Mac receives the clipboard update within a few seconds of reconnection — no manual restart needed

### Test 5: Pairing Flow

1. Unpair the devices
2. On Mac, navigate to the QR code screen
3. On Android, scan the QR code
4. **Expected:** Pairing completes within ~1 second of scan (previously up to 1s polling interval)
5. Verify clipboard sync works immediately after pairing

### Test 6: Remote Unpair Detection

1. With devices paired, unpair from the Android side
2. **Expected:** Mac detects the unpair within ~1 second and returns to the setup screen (previously up to 30s)

### Test 7: App Backgrounding / Wake (Mac)

1. Let the Mac go to sleep for 1+ minute, or close the laptop lid
2. Wake the Mac
3. Immediately copy text on Android
4. **Expected:** Mac receives the clipboard within a few seconds of waking (SSE reconnects on wake)

### Test 8: Service Restart (Android)

1. Force-stop the OTPSync app on Android
2. Re-open the app
3. Copy text on Mac
4. **Expected:** Android receives the clipboard update, confirming the SSE subscription re-established on service start
