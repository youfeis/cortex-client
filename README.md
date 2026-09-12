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
- Apple Health import: today's shared steps, active energy, weight, BP, and glucose.
- A Hide keyboard accessory above the iPhone keyboard, including numeric fields.
- Automatic calendar sync: the next 30 days from any selected iPhone calendars.
- A calendar picker groups personal/work calendars by account and shows counts.
- Calendar permission is requested from Calendars; once granted, refresh runs on
  launch, resume, EventKit change notifications, and every minute while open.
- Selection is saved per device. Denied access never deletes mirrored events.
- Health import remains manual. Calendar and Health access are read-only.
- This version does not write to Google Calendar, set alarms, or promise sync
  while iOS has suspended or closed Cortex.

Google accounts must have Calendars enabled in iPhone Settings, and events must
appear in Apple Calendar. Signing in only inside the Google Calendar app is not
enough. See [Google's iPhone setup guide](https://support.google.com/calendar/answer/99358?co=GENIE.Platform%3DiOS&hl=en).

The chat header shows quota remaining and reset dates/times in phone-local time.
Details includes every reported bucket; the same account-wide view is available
beside Sessions in settings. It refreshes at most once a minute automatically
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

Apple Health import reads the latest available glucose sample today, retaining
its source identifier so repeat imports do not duplicate it. HealthKit meal
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
