# CleanStart — Technical feasibility & entitlement assessment

Research date: **2026-10-27**. Sources were Apple's documentation (retrieved as
the JSON behind developer.apple.com/documentation), the WWDC20 session
*Enable encrypted DNS* (10047), Apple Developer Forums answers from Apple DTS,
CleanBrowsing's published filter page, and DuckDuckGo's help pages. I also ran
DNS queries against CleanBrowsing's live DoH endpoint (results below).

## 1. Feasibility table

### Verified

| Capability | Evidence |
|---|---|
| An ordinary app can set a **system-wide encrypted DNS** configuration without a VPN using `NEDNSSettingsManager` + `NEDNSOverHTTPSSettings` (iOS 14+). | Apple docs; WWDC20 10047: *"your DNS settings will apply to all apps on the system"*. No tunnel, no extension process, no virtual interface. |
| The user **must enable it manually** in Settings › General › VPN & Device Management › DNS. | Apple docs, `isEnabled`: *"configurations are disabled until the user enables the configuration in the Settings app"*. |
| It applies on **Wi-Fi and cellular**. | `onDemandRules` only *restricts* where it applies. CleanStart uses a single `NEOnDemandRuleConnect` with `interfaceTypeMatch = .any`, so there are no exceptions. |
| **CleanBrowsing Family DoH endpoint** is `https://doh.cleanbrowsing.org/doh/family-filter/`, with bootstrap IPs 185.228.168.168, 185.228.169.168, 2a0d:2a00:1::, 2a0d:2a00:2::. | cleanbrowsing.org/filters. Queried live on 2026-10-27. |
| CleanBrowsing Family **blocks adult domains with NXDOMAIN** (SOA `cleanbrowsing.rpz.noc.org`). | Live queries: pornhub.com, xvideos.com → NXDOMAIN. Cloudflare resolves both normally. |
| CleanBrowsing Family **forces DuckDuckGo Strict Safe Search** at the DNS level. | Live: `duckduckgo.com` → CNAME `safe.duckduckgo.com`. DuckDuckGo documents that safe.duckduckgo.com always uses strict Safe Search. |
| Google/YouTube/Bing are forced to SafeSearch. | Live: www.google.com → 216.239.38.120 (forcesafesearch), www.youtube.com → 216.239.38.119, www.bing.com → strict.bing.com. |
| **Microsoft Entra / Teams / Outlook domains resolve normally** through CleanBrowsing Family. | Live: login.microsoftonline.com, login.live.com, graph.microsoft.com, teams.microsoft.com, outlook.office365.com all returned normal answers. |
| **Individual Screen Time authorization** (`AuthorizationCenter.requestAuthorization(for: .individual)`, iOS 16+), the `FamilyActivityPicker`, `ManagedSettingsStore` shields and `DeviceActivity` schedules. | Apple docs. Authorization is confirmed with Face ID / Touch ID / passcode. |
| Apple's adult-website filter is available to apps through `ManagedSettingsStore.webContent.blockedByFilter = .auto()`. | Apple docs (`WebContentSettings.FilterPolicy.auto`: *"the system blocks adult content"*). |
| The **owner can always revoke**. For individual authorization Apple says *"the system removes any restrictions that prevent the user from bypassing parental controls so the user can delete an authorized app"*. | Apple docs, `requestAuthorization(for:)`. |
| Settings **survive app relaunch and device restart** (stored by iOS, not by the app process). | The DNS configuration is in system network preferences. Managed Settings are system-applied. Both are independent of the app running. |

### Conditional (works, with requirements or caveats)

| Capability | Condition |
|---|---|
| `dns-settings` entitlement | Requires a **paid Apple Developer Program** membership ($99/yr). Apple DTS: Network Extension *"is not listed"* among Personal Team (free) capabilities. It is self-service on paid teams (no request form). |
| Family Controls entitlement | **Development**: paid team, self-service. Free Personal Teams get *"Personal development teams … do not support the Family Controls (Development) capability"*. **Distribution** (TestFlight/App Store): needs Apple's separate approval via the Family Controls distribution request form. For a personal install, a development-signed build is enough. |
| Development-signed install lifetime | Paid team profiles last up to a year; then re-run from Xcode. |
| VPN interaction | *"if a VPN is active, resolution within the VPN tunnel will use the VPN's DNS settings"* (WWDC20). Any VPN, including a work VPN, DuckDuckGo's VPN or a free VPN app, **bypasses** CleanBrowsing for tunnelled traffic. CleanStart warns when a VPN appears active (heuristic). |
| iCloud Private Relay | Apple's Private Relay overview: *"If a user has configured custom-encrypted DNS settings using a profile or an app, the DNS server specified will be used instead of ODoH."* Expected to coexist. Verify on device. |
| Only one DNS configuration at a time | Selecting CleanStart deselects any other DNS app or profile (including an employer-pushed one, unless MDM locks it). |
| Networks that block DoH | iOS marks the Wi-Fi network with a privacy warning and *"connections in apps will fail rather than compromise your privacy"* (WWDC20). It is designed to fail closed. Behaviour during a full CleanBrowsing outage is not documented explicitly, so it is a device test (plan item 11). |
| DuckDuckGo uses system DNS | DuckDuckGo for iOS is built on WebKit (`WKWebView`) and resolves names through the system, so it is covered. Exception: DuckDuckGo's subscription **VPN**, which is a VPN. Confirm on device with plan item 6. |
| Apple adult-website filter in DuckDuckGo | Applied by iOS to WebKit content. Whether it covers third-party WebKit browsers on iOS 26 is **not documented** by Apple. Verify on device. Developer reports show `.specific` domain lists behaving differently in Safari and third-party browsers. |
| Accountability delay | Enforced **only inside CleanStart**. A real, honest speed bump, but voluntary. |
| "Prevent deleting apps" (`application.denyAppRemoval`) | Applies to *all* apps while on. Removed instantly if Screen Time access is revoked. |
| Background re-verification | `BGAppRefreshTask` runs only when iOS decides to run it. Best-effort. |

### Unsupported (and not attempted)

| Capability | Why |
|---|---|
| Preventing the owner from removing the DNS setting or revoking Screen Time | No public API. Only supervised/MDM devices can lock these, and MDM is excluded by the requirements. |
| Uninstall protection that can't be undone | Not possible for individual authorization (see Apple quote above). |
| Filtering images or videos on *allowed* sites | DNS works per domain. Nothing on stock iOS inspects page content without TLS interception, which is excluded. |
| Filtering traffic inside a VPN | VPN DNS takes precedence by design. |
| Reading Finch data | No public integration. |
| Detecting *which* DNS server is active when it isn't CleanStart's | NEDNSSettingsManager reports only the app's own configuration. CleanStart instead **measures** behaviour with probe lookups, which works for profiles too. |
| Packet tunnel, DNS proxy, content filter providers, HTTP proxies, root certificates, MDM | Explicitly excluded by you. CleanStart links only `NetworkExtension` for `NEDNSSettingsManager`. |

## 2. Entitlement assessment

| Entitlement | Target(s) | Value | Personal (paid dev) | TestFlight / App Store |
|---|---|---|---|---|
| `com.apple.developer.networking.networkextension` | App | `[dns-settings]` | ✅ self-service on paid team | ✅ self-service |
| `com.apple.developer.family-controls` | App, monitor ext, shield ext | `true` | ✅ "Family Controls (Development)" | ⚠️ requires approval: developer.apple.com/contact/request/family-controls-distribution |
| `com.apple.security.application-groups` | App, monitor ext | `group.<your bundle id>` | ✅ | ✅ |

There is **no** VPN, packet-tunnel, DNS-proxy, app-proxy or content-filter
entitlement anywhere in the project.

**Bottom line:** with a paid Apple Developer Program membership and a Mac (or
a rented/remote Mac) running Xcode 26, every component builds and installs on
your own iPhone. Without a paid membership, the DNS layer can still be had by
installing CleanBrowsing's official `.mobileconfig` profile manually, and the
habit tracker works. Screen Time and in-app DNS management need the paid
membership.

## 3. Persistence

| Event | DNS setting | Screen Time shields / web filter | Habit data |
|---|---|---|---|
| App closed or force-quit | stays | stays | stays |
| Phone restart | stays (system preference) | stays | stays |
| Network change (Wi-Fi ↔ cellular ↔ other Wi-Fi) | stays (catch-all rule) | n/a | n/a |
| App deleted | iOS removes the app's network configurations (confirm with plan item 15) | removed | deleted |
| Owner deselects in Settings | off immediately | — | — |
| Owner revokes Screen Time access | — | all removed immediately | — |

## 4. What the owner can disable vs. what an app can enforce

* **Owner can always:** deselect or remove the DNS setting, revoke Screen Time
  access, delete the app (after turning off "Prevent deleting apps" or revoking
  access), install a VPN or another browser with its own DNS, and turn off
  DuckDuckGo Safe Search (DNS still forces strict mode while the filter is on).
* **iOS enforces while enabled:** DNS filtering for all apps outside VPN
  tunnels, shields on chosen apps/categories/sites, Apple's adult-website
  filter, and app-deletion protection.
* **CleanStart enforces (voluntary):** the accountability delay before it will
  weaken its own settings, plus automatic verification and warnings.
* **Strongest legitimate friction:** ask a trusted person to set a **Screen
  Time passcode** you don't know (Settings › Screen Time › Lock Screen Time
  Settings), and turn on Content & Privacy Restrictions › App Store, Media, Web
  & Games › Web Content › *Limit Adult Websites*. This is Apple's own feature
  and works alongside CleanStart. Whether that passcode also guards revoking a
  self-authorized app's access is undocumented, so test it.
