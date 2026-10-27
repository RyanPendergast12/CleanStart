# CleanStart — Test results

Date: 2026-10-27. **Nothing here was run on a physical iPhone or in the iOS
Simulator.** Every device behaviour in [TEST_PLAN.md](TEST_PLAN.md) is still
untested.

## Environment audit

The session ran in a cloud Linux container (Ubuntu 24.04, x86_64), not on your
own computer, so I couldn't inspect your machine. Xcode can't run on Linux, so:

* All platform-independent logic lives in the `CleanStartCore` Swift package,
  which builds and tests on Linux with the open-source Swift 6.1.2 toolchain.
* The iOS app and extensions were compiled on a **GitHub Actions macOS
  runner**, a legitimate remote macOS build environment, with
  `xcodebuild` (unsigned, `generic/platform=iOS`).

## Results

| Check | Where | Result |
|---|---|---|
| `CleanStartCore` unit tests: 49 run (verification verdicts, protection assessment, accountability ledger, streaks, storage, diagnostics, real `getaddrinfo`) | Linux (Swift 6.1.2), local and CI | ✅ 49 passed, 0 failed (2 live tests skipped in the default run) |
| Same unit tests | macOS CI runner | ✅ passed |
| **Live probe test vs. real CleanBrowsing Family DoH** (`CLEANSTART_LIVE_TESTS=1`) | Linux, local and CI | ✅ verdict **verified**: control lookups resolved, both adult domains NXDOMAIN, duckduckgo.com → safe.duckduckgo.com, www.google.com → 216.239.38.120 |
| **Live negative test vs. unfiltered resolver** (Cloudflare 1.1.1.1 DoH) | Linux, local and CI | ✅ verdict **not filtering**. The verifier doesn't produce false "verified" results. |
| XcodeGen project generation (XcodeGen 2.46.0) | macOS CI | ✅ |
| iOS build of app + DeviceActivity monitor extension + shield extension (Debug, unsigned) | macOS CI, newest Xcode on the runner | ✅ `** BUILD SUCCEEDED **`, 0 compiler warnings in project code (CI run 40459369737, commit baccaa9) |
| Code signing with the DNS Settings / Family Controls entitlements | — | ⛔ Not possible without your Apple Developer team |
| Installation, DNS activation, Wi-Fi/cellular filtering, DuckDuckGo, Screen Time, Teams | — | ⛔ Requires your iPhone. See TEST_PLAN.md |

## Bugs found and fixed by the tests

1. `AccountabilityDelay.none` collided with `Optional.none`, so a request to
   reduce the delay to "none" was silently read as `nil`. I renamed the case
   to `.off`.
2. ISO-8601 date encoding dropped fractional seconds, so saved data didn't
   round-trip exactly. I switched to lossless encoding.
3. A check that was *inconclusive* (offline) could hide a later regression
   from "verified" to "not filtering". Regression detection now skips
   inconclusive runs.

## Raw DNS evidence (CleanBrowsing Family DoH, 2026-10-27)

```
example.com               NOERROR  A 172.66.147.243 …
login.microsoftonline.com NOERROR  CNAME … → A 40.126.24.81 …
teams.microsoft.com       NOERROR  CNAME teams.office.com … → A 52.123.129.14
graph.microsoft.com       NOERROR  normal answers
outlook.office365.com     NOERROR  normal answers
duckduckgo.com            NOERROR  CNAME safe.duckduckgo.com → A 52.149.247.1
duckduckgo.com (AAAA)     NOERROR  no data (no IPv6 bypass)
www.google.com            NOERROR  A 216.239.38.120 (forcesafesearch)
www.youtube.com           NOERROR  A 216.239.38.119 (restrict)
www.bing.com              NOERROR  CNAME strict.bing.com …
pornhub.com, xvideos.com  NXDOMAIN SOA cleanbrowsing.rpz.noc.org
reddit.com                NXDOMAIN (mixed content, blocked by Family filter)
nordvpn.com               NXDOMAIN (VPN provider, blocked by Family filter)
```

The same adult domains resolve normally through Cloudflare, which confirms
that the block comes from CleanBrowsing.
