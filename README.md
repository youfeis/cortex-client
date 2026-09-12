# External Prefrontal Cortex

An iPhone-first Flutter client for the private Cortex personal manager.

Two tabs: **Chat** and **My space**. Chat is one continuous main conversation,
with photos, steering, stop, context and quota usage, and in-app Codex login. My space
shows fitness and time-management progress. Most record changes happen through
chat. Money and personal targets are placeholders.

## Run

```sh
flutter pub get --enforce-lockfile
flutter run
```

The app connects to `https://cortex.miaotutu.com`. Pair it with a one-use code
generated on the server (`docker compose exec -T api cortex pair`). Each iPhone
creates its own P-256 Secure Enclave key. The private key stays on the phone.
The simulator uses its own Keychain key. No app-wide secret or user health
record is bundled in source or builds.

The server keeps the owner-to-main-session relationship and long-term memory
in MongoDB. Remaining context is an estimate from Codex's latest usage report;
unknown values remain unknown. Saved memories survive context compaction.

## iPhone features

- Camera and photo library attachments (up to four photos per message).
- Automatic Apple Health sync after setup: steps, active energy, weight, BP and glucose.
- A Hide keyboard accessory above the iPhone keyboard, including numeric fields.
- Google Calendar is the master source: personal/work accounts link in Settings.
- One calendar selection is stored on the server and shared by all devices.
- The next 30 days sync every five minutes on the server, including while Cortex
  is closed; launch/resume, pull-to-refresh and selection changes refresh sooner.
- Google consent replaces iPhone Calendar permission. EventKit import is removed.
- Google changes go through chat; Health still uses read-only iPhone permission.
- Phone alarms and background Health sync while iOS suspends Cortex are not included.

Old iPhone calendar entries stay visible until the first successful Google sync.
The server archives those old mirrors before replacing them. Sync errors retain
saved events; they never act as an empty calendar. Shared calendars and shared
invitations are deduplicated by source identity, not by matching titles.

The app header shows two compact remaining-capacity bars: main-session context
and Codex weekly quota, with the reset date/time in phone-local time. The main
context display keeps its last valid sample and updates once a minute; missing
heartbeat values do not clear it. Chat status stays live. Other
quota buckets are omitted. The same weekly quota is available beside Sessions
in settings. It refreshes at most once a minute automatically
and on explicit refresh. Unavailable/expired usage never becomes a fictional
100% balance. See [Codex account rate limits](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

Time management shows pending to-dos by deadline and a collapsed completed list.
Give Cortex a title and deadline in chat; changes and completion also happen in
chat. A date-only deadline stays due through the day. If no duration is supplied,
day planning uses a 25-minute estimate. My space uses accessible vector artwork
for Time and Fitness; stubs remain plain.

Meals require the owner to review photo estimates through chat. Fitness data
is real server data; an empty log is not treated as a complete food diary.
Apple Health active energy is shown separately from manual exercise to avoid
adding a second copy of the same workout into the TDEE estimate.

## Fitness trends

Fitness has Today and Trends views. Trends shows weight, glucose, and paired
blood pressure readings with All / 7 / 30 / 90-day ranges and tap/drag inspection.
Weight uses one latest reading per date and a calendar-based seven-day average.
Blood pressure retains each paired reading. Glucose can display mmol/L or mg/dL;
fasting, before-meal, after-meal, and unspecified readings stay separate.
Missing dates are not treated as zeroes. Charts do not diagnose readings.

Apple Health sync retains each available glucose sample from the last 90 days,
using its source identifier so repeat reads do not duplicate it. HealthKit meal
timing is preserved; before-meal samples are not assumed fasting. See
[Apple glucose metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeybloodglucosemealtime).

## Branches and builds

Develop on `dev`; merge a reviewed PR into `main`. Dev/PR run analysis and widget
tests. Main builds an unsigned iPhone release and an Apple Silicon simulator
app. Download them from the GitHub Actions artifact. **The unsigned build is
not directly installable on a physical iPhone.**

For a signed local iPhone installation using this Mac's configured Apple team:

```sh
scripts/install-iphone.sh DEVICE_IDENTIFIER
```

The script uses a release build so the app can launch without an attached
Flutter debugger. TestFlight automation still needs App Store Connect app/signing
setup; no TestFlight upload or App Store publication is configured.

## Validate

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug
flutter build ios --release
```

Optional native integration check against production (use a dedicated test
pairing code; never commit it):

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d SIMULATOR_ID \
  --dart-define-from-file=PRIVATE_PAIRING_JSON
```

The private JSON contains `CORTEX_PAIR_CODE`. The integration check pairs the
simulator, verifies private data screens and draft retention, and writes
screenshots to ignored `build/screenshots/`. It does not send a chat message,
modify the owner's records, or sign in to an OpenAI account.


## Native shell and remote layouts

`lib/app/shell.dart` owns the two tabs. Features are grouped under `lib/features/`
(chat, space, fitness, time, settings); networking and durable state are in
`lib/core/`. `lib/remote_ui/` validates layout documents and compiles their
allowlisted component trees into Flutter's `rfw` runtime. Chat controllers,
streaming, steering/stop, file selection, permissions and signing remain native.
The server can rearrange feature blocks, cards, chat/composer slots and message
bubble presentation without reinstalling the app. New native capabilities still
require an app update.

The signed `/v1/ui` response is versioned and stored in MongoDB. Last validated UI
is cached on the phone; the included release is the offline fallback. Unknown
schemas/components, missing/duplicate controls and oversized documents are
rejected. Layout activation waits until typing and a running reply finish.
Checks run on opening/resuming the app and every three minutes while active.

Edit the server's `internal/cortex/ui/release.json` and give it a new revision.
Run `dart run tool/check_layout.dart ../server/internal/cortex/ui/release.json`
from this repository, then merge the server change to main to publish it. The
bundled copy only needs changing when preparing a new client release.

## Automatic phone data

Health reads run after setup, on launch/resume, once per minute while active, and
when HealthKit reports a change. The last 90 days of weight, paired blood
pressure and glucose are upserted by sample UUID. Daily activity covers today
and the prior seven days; HealthKit combines phone/watch sources. No manual
import is required. Empty or denied reads never erase saved measurements.
Apple does not reveal per-type Health read authorization; “Access requested” is
not a claim that every data type was granted. Change permissions in Apple Health.
Background execution while iOS suspends the app is not implemented.

Google Calendar uses server OAuth and a shared server-side calendar selection.
The native bridge supplies only the current IANA time zone, with no EventKit
permission or event upload. Settings links each personal/work Google account.

## Avatars

Cortex uses a small vector owl drawn in Flutter. The owner's photo is fetched
through signed image requests, with its ID in the private owner-avatar memory
record. No personal picture is committed or bundled. The initial picture came
from the owner's Mac account image; iOS has no direct Apple Account avatar API,
so it is not claimed to be a live iCloud-photo sync.

Medical routines with `intervalWeeks` and `anchorDate` show their repeat interval
and next due date. Daily routines retain their existing labels. Retired routines
are hidden from both Fitness and Time management.

## Alarms, helpers and saved memory

On iOS 26, Settings > Phone permissions > Alarms requests AlarmKit permission.
Create/change/cancel alarms through chat; Time management shows the current
phone status. Commands are device-bound and only confirmed after AlarmKit
succeeds. New commands wait while the phone is offline or suspended. Existing
system-scheduled alarms do not need the server to ring. Cortex manages its own
alarms, not the Clock app's existing entries. Initial support is one-time and
weekly alarms with the system Stop control.

The native UUID/revision ledger prevents duplicate scheduling on network retry.
Changing an alarm cancels/replaces it; a failed replacement attempts to restore
the previous schedule and reports the result. Never uninstall the app just to
update it: its pairing key and local alarm receipts must be preserved.

Helpers appear in Memory & settings with title, status, summary and context.
A short working status stays in the main chat. Saved-memory snackbars come from
committed server events; their displayed IDs persist locally across restarts.

`flutter drive --driver=test_driver/integration_test.dart --target=integration_test/alarm_test.dart -d SIMULATOR_ID`
checks native authorization, one-time/weekly scheduling, duplicate retries,
replacement, stale revisions, the actual alerting state, and cancellation. It
uses a single fixed test UUID and removes that test alarm in cleanup. Allow the
system permission prompt on the test simulator; never run this ringing test on
a user's physical phone without arranging it with them.
