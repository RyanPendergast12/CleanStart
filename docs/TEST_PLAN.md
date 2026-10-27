# CleanStart — Device verification plan

**Status: none of these steps have been run on a physical iPhone.** They
need your device. Record results in the last column. The automated tests that
*were* run are in [TEST_RESULTS.md](TEST_RESULTS.md).

Safety rules for every step:
* Explicit-content checks use **DNS lookups only** (CleanStart › Diagnostics).
  Never open the test domains in a browser.
* Before steps 3, 12 and 13, note how to restore: Settings › General › VPN &
  Device Management › DNS › Automatic.

| # | Area | Steps | Expected | Result |
|---|---|---|---|---|
| 1 | Installation | Generate the project, set your team/bundle IDs, run on the iPhone from Xcode. Trust the developer in Settings › General › VPN & Device Management if prompted. | App launches and shows onboarding. | ☐ |
| 2 | Entitlements | Xcode › target › Signing & Capabilities shows **Network Extensions › DNS Settings**, **Family Controls (Development)** and **App Groups** for the app; Family Controls (+ App Groups) for both extensions. No signing errors. | All capabilities present, no errors. | ☐ |
| 3 | DNS install | Protection › DNS Filtering › Install. Then Settings › General › VPN & Device Management › DNS › select CleanStart. Return to the app. | Status changes "Not installed" → "Installed, not enabled" → "Enabled". **No VPN icon** in the status bar. | ☐ |
| 4 | Wi-Fi filtering | On home Wi-Fi: Diagnostics › Run filtering check. | Verdict **Filtering verified**. All 6 probes pass. Connection shows Wi-Fi. | ☐ |
| 5 | Cellular filtering | Turn Wi-Fi off. Run the check again. Repeat on a second Wi-Fi network (e.g. work or café). | **Filtering verified** on Cellular and on the other Wi-Fi. | ☐ |
| 6 | DuckDuckGo | In DuckDuckGo search a neutral word and open Settings › Search: Safe Search should be forced strict (DNS). Try opening `reddit.com` (a mixed-content site CleanBrowsing blocks, not explicit). | Safe Search behaves as Strict. reddit.com fails to load (blocked by DNS). | ☐ |
| 7 | Private browsing | Use DuckDuckGo's Fire Button, then repeat the reddit.com check. In Safari, open a Private tab and repeat. | Still blocked in both. | ☐ |
| 8 | Screen Time permission | Protection › Screen Time › Connect. Approve with Face ID. Also try denying once (then re-authorize). | Status Approved. Denial shows a clear message and nothing breaks. | ☐ |
| 9 | App shielding | Pick a non-work test app (e.g. a game or a second browser). Save. Open it. Then try a schedule that includes "now". Turn on the Apple adult-website filter and re-test reddit.com in **DuckDuckGo** and Safari. | CleanStart shield screen appears. Schedule applies within a minute. Record whether Apple's filter acts inside DuckDuckGo. | ☐ |
| 10 | Restart persistence | Restart the iPhone. Don't open CleanStart. Retry the shielded app and reddit.com. Then open CleanStart. | Shield and DNS blocking still active before opening the app. Check on open still says verified. | ☐ |
| 11 | DNS provider outage | Simulate: on Wi-Fi, use a router or firewall rule to block 185.228.168.0/24, 185.228.169.0/24 and `doh.cleanbrowsing.org` (or test on a captive/hotel network). Run the check, try a normal site. | Lookups **fail** (no internet for names) rather than silently resolving unfiltered. The check shows **Inconclusive**, not Verified. Record actual behaviour. Restore with the DNS › Automatic step if needed. | ☐ |
| 12 | Teams / Authenticator | Run Protection › Teams & work apps checklist on Wi-Fi **and** cellular: Teams sign-in, messages, a call, Authenticator push, code, Entra web sign-in, Company Portal compliance. | Everything works as before enabling. | ☐ |
| 13 | Filter removal | Request removal (with a delay, observe the wait). Apply it after the delay. Also test removing directly in iOS Settings. Run the check. | After either removal the check reports **Not filtering**, and the dashboard shows the regression warning. | ☐ |
| 14 | Network recovery | After 13, confirm normal browsing, Teams and cellular all work. Re-install and confirm verified again. | Clean recovery both ways. | ☐ |
| 15 | Uninstall | Turn off "Prevent deleting apps", remove restrictions, delete CleanStart. Check Settings › General › VPN & Device Management (DNS) and Screen Time. | No CleanStart DNS entry and no shields remain. Internet normal. | ☐ |

Extra checks worth doing:
* With **iCloud Private Relay** on, run step 4 again.
* With your **work VPN** (if any) connected, run the check: expect a VPN warning
  and possibly "Not filtering" for that period. That's expected and safe.
* Set a **Screen Time passcode** held by a friend, then see whether revoking
  CleanStart's Screen Time access asks for it. Record the result; Apple doesn't
  document it.
