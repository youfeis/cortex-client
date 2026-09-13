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
- Opening or resuming Cortex re-reads Health, including when an earlier sync is
  still running. Fitness pull-to-refresh does the same. A post-upload snapshot
  keeps steps, estimated TDEE, food budget and the calorie bar in sync.
- A Hide keyboard accessory above the iPhone keyboard, including numeric fields.
- Chat follows the latest message when the iPhone keyboard opens or closes,
  after the resized message list settles. Ordinary history scrolling stays free.
- Chat opens at the end on cold launch, app resume and returning to the Chat tab.
  Newest messages anchor a reversed list at offset zero, so loading long history,
  streaming text or replacing the remote layout does not rely on an estimated
  total scroll height. Background data refreshes do not force a jump while reading.
- Google Calendar is the master source: personal/work accounts link in Settings.
- One calendar selection is stored on the server and shared by all devices.
- The next 30 days sync every five minutes on the server, including while Cortex
  is closed; launch/resume, pull-to-refresh and selection changes refresh sooner.
- Google consent replaces iPhone Calendar permission. EventKit import is removed.
- Google changes go through chat; Health still uses read-only iPhone permission.
- Cortex alarms use native AlarmKit. Background Health sync while iOS suspends Cortex is not included.

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

Time management separates Due today from other deadlines, with a collapsed completed list. Today follows the phone-local calendar date, including earlier timed deadlines today.
Give Cortex a title and deadline in chat; changes and completion also happen in
chat. A date-only deadline stays due through the day. If no duration is supplied,
day planning uses a 25-minute estimate. My space uses accessible vector artwork
for Time and Fitness; stubs remain plain.

Meals can be logged from photos using researched, clearly marked estimates. Fitness data
is real server data; an empty log is not treated as a complete food diary.
Apple Health active energy is shown separately from manual exercise to avoid
adding a second copy of the same workout into the TDEE estimate.
The daily Health step total takes priority over chat-entered totals. The energy
calculation uses the stored baseline TDEE, calories for steps above the stored
baseline, and logged workouts, then subtracts the stored deficit for the food
budget. Refreshing never changes the owner's targets. Failed reads retain the
last saved data and retry automatically; missing Health readings do not mean zero.

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

## Nutrition and routine checkboxes

Fitness shows daily energy, protein, carbs, fat, saturated fat, fibre, added
sugar and sodium. Unknown nutrients stay blank; partial totals say how many
meals are known. Food entries show semantic icons and portion-specific flags,
with estimates, assumptions and source links in expanded details. General high
nutrient flags use the [FDA 20% Daily Value guide](https://www.fda.gov/food/nutrition-facts-label/how-understand-and-use-nutrition-facts-label):
sodium 460 mg, added sugar 10 g, saturated fat 4 g, fibre 5.6 g per shown portion.
These are label-reading aids, not personal targets or a clinical food score.

Saved food facts is a searchable, paginated library of names and facts, without
photo storage. A food-photo log describes food eaten; the separate library photo
action saves facts only. Chat handles portions, corrections and future reuse.
Food facts and meal history stay separate from permanent personal memories.

Fitness routines show today's checkboxes plus a collapsed Other days section.
The server matches actual measurements, exact movement routine IDs, and explicit
chat/checkbox/day-plan completion. Doses never complete from a schedule or meal.
Source captions explain why a box is checked. A checkbox correction overrides
auto-matching for that date; tomorrow starts fresh. Off-day rotation checkboxes
are disabled. Day-plan status uses the same routine completion state.

## Task cards and check-ins

Tell chat “I'm starting…” or tap Start on a to-do/day-plan task. A current-task
strip stays in both tabs and opens the full task controls. The task sheet uses
a fixed Close button above the scrolling list, plus a drag handle;
the same sheet opens from Live Activity links. Closing it leaves timers running.
Completing a linked task completes its to-do. Pausing/postponing stops reminders without completing
work; silence never marks a task done. Google Calendar changes require planning.

Overlapping tasks share one 160-point native Live Activity. Two columns show
independent progress and 44-point-high buttons: Start/Done/Resume, the clock-arrow
Postpone button, Pause and +5/+10/+15 minutes. Titles open task details. With
more than two tasks, 44-point arrow buttons show the next or previous pair
without opening Cortex; the left arrow shows the page count. Paging is saved
locally and never edits timers, revisions or the action history. Task positions remain stable when the
server returns its latest-edited task first. Both the in-app strip/details and
Live Activity pages show tasks only from 30 minutes before their planned start,
or after an explicit Start. Already-started paused/postponed tasks stay reachable
with Resume; unstarted postponed work stays hidden until rescheduled.

Selected timed Google events and scheduled day-plan to-do blocks automatically
create durable task occurrences. Planned tasks use pending → ready (30 minutes
before scheduledStart) → active (explicit Start) → done (explicit completion),
with paused/postponed/cancelled branches. Starting early is allowed. Rescheduling
returns to pending/ready. Clock activation never changes the owner-action revision.

On iOS 26, the phone queues standard ActivityKit cards using the scheduled-start
API, which activates without a running Flutter app. Pending cards are reported as
scheduled, never as currently visible. Nearby tasks share one board; groups span
at most eight hours, with three queued boards. Each card carries the displayed
pair only; its arrows load other tasks from native storage to stay below the
4 KB payload limit. Later pending tasks stay in the scheduling cache and calendar,
without appearing in the current-task list or adding Live Activity pages.
iOS may accept fewer cards; per-task acknowledgement reports actual coverage.
The first scheduled card's alert replaces the matching ordinary 30-minute alert.
Opening Cortex refreshes the next 48 hours, replaces moved/deleted occurrences,
and replenishes the bounded queue. Calendar changes made after the last phone
sync need another sync; this release does not claim APNs delivery of new events.

Completed to-dos remain visible and crossed out. Done today uses their persisted
completion timestamp in the phone's local time. Older/undated completions are
expanded separately; editing a completed task does not move its completion date.

Reopening Cortex restores cached unfinished tasks before network access succeeds.
Bounded local retries handle iOS scene activation delays. Activity lifecycle
changes refresh the displayed status; expiry can renew while Cortex is open.
Swiping away a card is respected until reopening or an explicit task update.
Settings > Task check-ins shows availability and has Restore task card.
Apple can end a Live Activity after eight hours; a continuously visible card
cannot be guaranteed while the app remains closed. Tasks remain stored.

Button actions save locally before syncing with the signed API. App Intents try
to sync directly; offline/locked-device failures remain queued for the next open.
Revision checks reject stale actions. The server forwards real starts, extensions
and postponements to the main chat when idle. Postpone opens a reason sheet;
expanded reminder notifications also accept a typed/dictated reason.

Reminders fire at the expected finish, after ten minutes, then every fifteen
minutes (or chat-selected thirty), within the latest plan’s waking hours.
Up to forty reminders total are pre-scheduled across tasks and refreshed on open,
bounded to eight hours of check-ins. Notification/Focus permissions control alerts.
Pausing, postponing or completing a task cancels only its reminders.

Settings > Task check-ins > Preview overlapping task card provides two test timers
when there are no real open tasks. The same flow is available at
`cortex://focus?action=preview`. Preview timers are excluded from planning and stats.

Native verification (idle simulator only):
`flutter drive --driver=test_driver/integration_test.dart --target=integration_test/focus_test.dart -d SIMULATOR_ID`
checks real notification delivery, one shared card, independent offline actions,
stable task positions, started paused/postponed visibility, future-task filtering,
foreground restoration and stale-action rejection. Synthetic tasks are removed.

## Pets

My space → Pets shows separate Cookie and Wanwan weight charts with 30-day, 90-day and all-history filters. Every same-day reading is retained, values use two decimal places in kg, and the axis leaves room for small changes. Use the chat links to record or correct a weight; pull down to refresh. The Pets page and My space entry use the existing database-backed remote layout contract with a bundled offline layout. Missing readings remain empty.
