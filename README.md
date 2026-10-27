# CleanStart

A private, local-only iPhone app that helps you keep pornography out of your
day. It does that with three layers that Apple supports:

1. **System-wide adult-site filtering through encrypted DNS.** This uses
   `NEDNSSettingsManager` with DNS-over-HTTPS to **CleanBrowsing Family**. It
   works on Wi-Fi and cellular, in DuckDuckGo and every other app.
   **No VPN, no tunnel, no proxy, no certificates.**
2. **Screen Time protection.** You can shield chosen apps, categories and
   websites (always or on a schedule), turn on Apple's adult-website filter,
   and optionally block app deletion.
3. **Habit building.** A daily porn-free check-in, optional streaks, goals and
   supportive feedback. All of it stays on your phone.

CleanStart also **verifies** that filtering actually works. It runs DNS-only
probe lookups and keeps "is a setting saved?" separate from "are adult domains
really blocked on this network right now?". It is honest about limits: you own
the iPhone, so you can always undo all of this in iOS Settings.

* Feasibility, entitlements and limitations: [docs/FEASIBILITY.md](docs/FEASIBILITY.md)
* Device test plan: [docs/TEST_PLAN.md](docs/TEST_PLAN.md)
* What was actually tested: [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md)

---

## What you need

| Need | Why |
|---|---|
| iPhone on iOS 17 or later (you're on iOS 26) | Deployment target |
| **Paid Apple Developer Program** membership ($99/yr) | The DNS Settings and Family Controls entitlements aren't available to free Personal Teams |
| **A Mac with Xcode 26**, or a legitimate remote Mac (MacinCloud, AWS EC2 Mac, or a friend's Mac) | Xcode is the only supported way to sign and install a development build. It does not run on Windows or Linux. |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) | Generates `CleanStart.xcodeproj` from `project.yml` |

> **No paid account?** You can still get the DNS layer today, without this
> app: in Safari open <https://cleanbrowsing.org/filters/> and choose Family
> Filter › Apple devices to download CleanBrowsing's official `.mobileconfig`.
> Install it in Settings › General › VPN & Device Management. Then use
> DuckDuckGo with Strict Safe Search and Apple's own Screen Time
> *Limit Adult Websites*.

## Project layout

```
CleanStartCore/            Swift package: all platform-independent logic + unit tests
  Sources/CleanStartCore/
    DNS/                   CleanBrowsing provider, system resolver, probes, verifier
    Protection/            Configuration-vs-effectiveness assessment
    Accountability/        Delay ledger for weakening changes
    Habits/                Check-ins, streaks, goals, encouragement
    Storage/               Local JSON store (data-protected, excluded from backup)
    Compatibility/         Teams / Authenticator checklist
    Diagnostics/           Privacy-safe text report
App/CleanStart/            SwiftUI app
  Services/                NEDNSSettingsManager, NWPathMonitor, FamilyControls,
                           ManagedSettings + DeviceActivity, local notifications
  Views/                   Today, Protection, Habits, Diagnostics, Settings
Shared/                    Code shared by the app and the schedule extension
Extensions/
  ActivityMonitor/         DeviceActivityMonitor: applies scheduled shields
  ShieldConfiguration/     Custom, discreet shield screen
project.yml                XcodeGen spec (targets, entitlements, Info.plist)
.github/workflows/ios.yml  CI: core tests on Linux/macOS + unsigned iOS build
```

## Install on your iPhone

1. On the Mac: `git clone` this repository, then:
   ```sh
   brew install xcodegen
   ```
2. Edit the top of `project.yml`:
   ```yaml
   DEVELOPMENT_TEAM: "ABCDE12345"                  # Xcode › Settings › Accounts › your team
   CLEANSTART_BUNDLE_ID: com.yourname.cleanstart   # anything unique
   CLEANSTART_APP_GROUP: group.com.yourname.cleanstart
   ```
3. Run `xcodegen generate`, then open `CleanStart.xcodeproj`.
4. Select the **CleanStart** target › *Signing & Capabilities*. Automatic
   signing should register the App ID, the App Group and these capabilities:
   **Network Extensions (DNS Settings)**, **Family Controls (Development)**
   and **App Groups**. Check the two extension targets too. If Xcode reports a
   capability is missing, enable it for the App ID at
   developer.apple.com › Certificates, IDs & Profiles.
5. Connect your iPhone and turn on Developer Mode (Settings › Privacy &
   Security › Developer Mode, then restart). Choose it as the run destination
   and press **Run**.
6. If iOS asks, trust the developer in Settings › General › VPN & Device
   Management.

A development build signed by a paid team keeps working for up to a year. To
renew, run it from Xcode again. Your data is kept.

## Activate DNS filtering

1. CleanStart › **Protection › DNS Filtering › Install DNS filtering**, then confirm.
2. iPhone **Settings › General › VPN & Device Management › DNS** › select
   **CleanStart**. iOS requires this manual step.
3. Back in CleanStart, the status reads **Enabled**. Then go to **Diagnostics ›
   Run filtering check**. You want **Filtering verified**.

The status bar shows no VPN icon, because this isn't a VPN.

## Verify on Wi-Fi and cellular

* **Wi-Fi:** Diagnostics › Run filtering check. The result should be
  *Filtering verified* on "Wi-Fi".
* **Cellular:** turn Wi-Fi off, then run the check again. It should be
  *verified* on "Cellular".
* **Another Wi-Fi:** repeat on a work or public network.
* CleanStart re-checks on its own every time you open it. If filtering stops
  working (for example a VPN connects or the setting is removed), the Today
  screen says so. If background checks run, you also get a notification.

**What the check does:** it resolves `www.apple.com` and
`login.microsoftonline.com` (controls), two well-known adult domains (these
must be blocked), and `duckduckgo.com` / `www.google.com`, which must be
redirected to SafeSearch. It performs **DNS lookups only** and never loads any
page. A run where nothing resolves is reported as *Inconclusive*, never as
*verified*.

## DuckDuckGo

DuckDuckGo for iOS resolves sites through the system DNS, so CleanBrowsing
covers it in normal tabs and after using the Fire Button. CleanBrowsing also
rewrites `duckduckgo.com` → `safe.duckduckgo.com`, which forces **strict Safe
Search** at the network level. As a second layer, set DuckDuckGo › Settings ›
Search › Safe Search to **Strict** yourself. Don't turn on DuckDuckGo's
subscription VPN: like any VPN, it uses its own DNS. You don't need to switch
to Safari. See [FEASIBILITY.md](docs/FEASIBILITY.md) for the details and
limits.

## Microsoft Teams & work safety

* CleanStart never touches work traffic, credentials or tokens. It has no VPN,
  proxy, certificate or MDM component.
* On 2026-10-27, CleanBrowsing Family resolved the Entra, Teams, Graph and
  Outlook sign-in domains normally.
* Changing DNS *can* still affect work services in edge cases, for example
  internal company hostnames or a work VPN app whose domain is classed as
  "VPN/proxy" (that category is blocked by the Family filter).
* After enabling, run **Protection › Teams & work apps checklist** on Wi-Fi
  and cellular.
* **If your iPhone is managed by your employer** (Company Portal device
  enrollment that controls DNS), or policy forbids personal DNS settings,
  don't install the DNS layer. Use Screen Time shields, Apple's adult-website
  filter and DuckDuckGo Strict Safe Search instead. None of them change
  network settings.
* **Instant restore:** Settings › General › VPN & Device Management › DNS ›
  Automatic.

## Known limitations and potential bypasses

* **You can always turn it off.** Deselecting the DNS setting, revoking Screen
  Time access or deleting the app all work, because it's your iPhone.
  CleanStart's accountability delay (default 1 hour) only slows changes made
  *inside* CleanStart.
* **VPNs bypass DNS filtering** while connected. That includes free VPN apps,
  browser VPNs and DuckDuckGo's VPN. CleanStart warns when a VPN appears
  active, and CleanBrowsing blocks many VPN-provider domains.
* **Apps or browsers with their own built-in encrypted DNS** can skip the
  system resolver. Shield browsers you don't need.
* **Allowed sites with explicit images.** DNS filtering works per domain and
  can't see individual images or videos.
* **Mixed-content sites** such as Reddit are blocked entirely by the Family
  filter. That's a side effect you may or may not want.
* **Opt-in Screen Time items are not inspected by CleanStart.** The tokens are
  opaque, so CleanStart can't tell which apps you picked.
* **Background checks** run only when iOS chooses to run them.
* **Your DNS lookups go to CleanBrowsing.** That's inherent to DNS filtering.
  Read their privacy policy.

**Strongest legitimate friction:** ask someone you trust to set a Screen Time
passcode you don't know, then enable Content & Privacy Restrictions › Web
Content › *Limit Adult Websites*, and keep the CleanStart accountability delay
at 24 hours or more.

## Safe uninstall and rollback

1. **Fast restore:** Settings › General › VPN & Device Management › DNS ›
   Automatic.
2. **Inside CleanStart:** Protection › Screen Time › *Remove all restrictions*,
   then Protection › DNS Filtering › *Remove DNS filtering*. Both wait for the
   accountability delay. Optionally use Settings › *Delete all local data*.
3. **Without the app:** Settings › Screen Time › (apps with Screen Time
   access) › CleanStart › off. This removes every shield and filter.
4. If you enabled **Prevent deleting apps**, turn it off (step 2 or 3) first.
5. Delete CleanStart. Then check Settings › General › VPN & Device Management
   to confirm no DNS entry remains.
6. If you used CleanBrowsing's profile instead, remove it in Settings ›
   General › VPN & Device Management.

## Privacy

No account. No analytics, crash reporting, ads or third-party SDKs; there are
no package dependencies at all. No browsing history is recorded. Data lives in
the app's sandbox as JSON files protected by iOS Data Protection and excluded
from backups. Settings › Privacy lists exactly what's stored, and *Delete all
local data* removes it.

## Development

```sh
cd CleanStartCore
swift test                                        # unit tests (macOS or Linux)
CLEANSTART_LIVE_TESTS=1 swift test --filter Live  # probes vs. real CleanBrowsing DoH (DNS only)
```

CI (`.github/workflows/ios.yml`) runs the core tests on Linux and macOS, then
builds the app and both extensions for iOS without code signing.
