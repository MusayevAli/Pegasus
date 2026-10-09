# Verification — 8 October 2026 (9 October UTC)

## Delivered application

The existing `PegasusTripFit` Xcode project and `com.hackathon.PegasusTripFit` identity are retained. The main SwiftUI entry now uses the v2 integrated search, configuration, review and saved-trip flow. Earlier saved prototype trips remain accessible. The old notes/AI-designer modal is not part of the main flow.

The referenced Mobbin screen could not be accessed. The implementation follows the user's described spacious Apple Store direction, using Pegasus yellow, white surfaces, native typography/navigation and existing project imagery; it is a hackathon concept, not an approved airline release.

## Build and focused tests

- Native iOS target: **BUILD SUCCEEDED**, Xcode26.3 (17C529), generic iOS Simulator arm64/x86_64, iOS17 minimum. Actual UI execution: iPhone17Pro, iOS26.2. The system Xcode selection was not changed.
- Backend: **80/80 tests passed**, TypeScript build passed. Coverage includes inventory/chronology, schema/domain validation, missing-key/error behavior, exact alternative constraints, scoped baggage, cheapest eligible selections, quote expiry/repricing, checkout idempotency and analytics.
- Native v2 harness: **58 checks passed**, including stale/cancelled responses, lock preservation, ambiguous imports, correct local time, photo cancellation, persistence, incompatible selections, scope-preserving undo, opt-in event behavior, and interrupted checkout recovery. Real local HTTP booking also completed at€674.63 and retrieved the identical saved demo order. See [model report](booking-v2-model-verification.json). These are model tests, separate from simulator UI evidence.
- Native travel-memory harness: **26 privacy checks passed**, plus real HTTP opt-in, structured collection, actual OpenAI learning, locked correction, opt-out, export and erasure. Token access is scoped to the configured backend and stored in Keychain in the app. Harness uses an in-memory credential store and synthetic facts: [profile evidence](travel-profile-model-verification.json).
- Retained Swift domain suite: **20/20 tests passed**, covering family seats, bundle inclusion, scoped baggage, connection timing, DST and draft preservation.
- Dashboard production build passed. Browser inspection and analytics details are in [dashboard verification](../dashboard/VERIFICATION.md) and [analytics definitions](ANALYTICS.md).

## Genuine live model evidence

Server-side OpenAI Responses calls used structured schemas, configured `gpt-4.1-mini` text/vision, and actual image payloads. Request IDs, model IDs, latency and validated results are recorded without secrets or raw images:

| Exercise | Actual result | Evidence |
|---|---|---|
| Three unseen descriptions | BCN return2matches; AYT after10:00 two matches; BER return4matches, with distinct validated intents | [search](../backend/evidence/live-search-results.json) |
| Two visibly different packing photos | Suitcase/clothes/bags versus laptop; differing counts/categories and uncertainty | [packing](../backend/evidence/live-packing-results.json) |
| Two fictional event screenshots | BCN24Oct2026 15:00Europe/Madrid; BER29Oct2026 20:30Europe/Berlin | [imports](../backend/evidence/live-trip-import-results.json) |
| Incoming flight screenshot | British Airways JFK→LGW24Oct08:00Europe/London; separate-ticket onward search | [applied searches](../backend/evidence/live-import-search-results.json) |
| Flight comparison and no-match alternatives | Same-scope factual comparison; all three candidate alternatives successfully re-searched after explicit proposed changes | [comparison](../backend/evidence/live-comparison-results.json), [final alternatives](../backend/evidence/live-alternatives-results.json) |
| Customer learning | Real model selected 5 validated preferences from 3 fictional structured travel facts, with source, confidence and exact evidence IDs | [learning](../backend/evidence/live-personalization-results.json) |
| Aggregate airline insight | Live model selected a measured factual observation and supplied a validated qualitative hypothesis, change and experiment with exact evidence records | [insight](../backend/evidence/live-insight-results.json) |

Live image tests used public packing images and locally generated, prominently labelled fictional screenshots. Automatic approval review initially rejected an unverified screenshot upload; the images were then regenerated from inspected static text with a SHA256 manifest, approved, and tested. No rejected request was bypassed. A separate synthetic child-data live search was rejected; successful live searches used fictional adult-only cases, with family/child domain behavior covered by local tests.

## Native simulator observations

Three new descriptions were entered through the iPhone UI, each making a genuine model request and visibly changing flight cards:

1. SAW→BCN,24October2026,one adult,one-way,direct,no bag,€250budget: **€93.00** direct flight.
2. SAW→AYT,20October2026,after10:00,one adult,€80budget: **€35.10** and **€44.10** departures.
3. SAW→BER,18–21October2026,one adult,one checked bag both ways,no overnight,€500budget: **€195.50** and **€214.50** return choices.

Selected two Berlin offers, opened live comparison, continued with the cheaper offer, entered fictional guest names and inspected expandable baggage. Review itemisation was€147.50flights+€24outbound bag+€24return bag=**€195.50**; results, configuration, pinned total, review and confirmation agreed. Cancel checkout returned to configuration with names and choices preserved. A subsequent confirmed demo checkout saved **DEMO-577574BE**, explicitly **no charge/no ticket issued**, and appeared in My Trips alongside earlier prototype trips. The saved trip remained present after a simulator restart and reinstall of the updated app.

Actual UI review found and fixed toolbar branding compression, unnecessary initial validation copy, stale configuration totals, expired pending-checkout recovery, wrong upgrade-price labels, missing measurement accessibility labels and stale comparison selections. Backend live comparison review found UTC/local-time ambiguity and baggage assignment wording; both were corrected and live comparison re-run. AI comparison prose now stays qualitative, with airport-local times in authoritative rows.

See [Barcelona results](screenshots/ios-v2-results.png), [Antalya results](screenshots/ios-v2-antalya.png) and [confirmation](screenshots/ios-v2-confirmation.png).

## Measured effort and limits

The earlier preset family prototype required **10 observed action taps** from its Barcelona card to demo confirmation, excluding scrolling and with no typed guest fields. The current configured-trip path requires flight selection, review, review acknowledgement and demo completion, with guest names on the same configuration page. The tasks/inventory are not identical, so this is not a controlled percentage improvement. No human completion-time claim is made; tool latency makes automation duration unsuitable as a usability measure.

Native navigation, text entry, main-screen clipping and contrast were inspected. Full VoiceOver user testing, maximum Dynamic Type, physical-device camera/signing and iOS17 runtime execution remain separate checks unless recorded below. PhotosPicker opened natively. Fixture import initially stalled because the simulator bridge could not open images under the protected Documents path. Restarting only the simulator bridge and importing the public/fictional fixtures from `/private/tmp` succeeded. Native event import subsequently completed: selected the fictional Barcelona conference screenshot, extracted date24Oct2026/time15:00/venue/timezone, changed the airport buffer to180minutes, confirmed, and applied it to an ordinary sample search returning the eligible09:45arrival at€93. See [confirmation](screenshots/ios-event-confirmation.png) and [result](screenshots/ios-event-search-result.png). Later PhotosPicker coordinate automation intermittently failed with `noWindowsAvailable`, so a complete native packing photo→measurements→apply/undo journey remains unverified. The actual image HTTP calls and native state-model packing/apply/undo checks pass. The native profile consent and data entry navigation were inspected: [profile consent](screenshots/ios-travel-memory-consent.png). Actual native opt-in caught Keychain error -34018 in an unsigned simulator build; simulator-only application/keychain entitlements and ad-hoc signing were added, along with secure preflight and failed-setup cleanup regressions. Complete UI observation is recorded only when available, separate from real native API evidence.

## Integration boundaries

- **AI:** live model calls exercised; errors/refusals/invalid outputs produce an honest unavailable state. Manual/sample booking remains available with the backend running.
- **Inventory:** real public Pegasus MCP flight search is working, with separate explicit sample mode (2700 stable flights,15route pairs,30rolling days). Native HTTP exercised a two-adult24–30Oct return and compared real offers. Flexible search covers up to two destinations and three representative dates with bounded concurrency and explicit coverage notices; nearby-date alternatives preserve locked requirements. Provider flight prices, dates, party count, currencies and continuation links are validated; unknown extras and fare terms remain unknown.
- **Pegasus:** official `flight-search` advertised `noauth` and `readOnlyHint:true` and returned real availability without credentials. Authentication requirements are checked at runtime before use. Official Pegasus continuation links are validated against the query. No account/PNR tool was called. NDC extras, seat maps, repricing, orders and ticketing still require authorised partner integration. Public search is not live in-app ticket issuance.
- **Payments:** demo only. Retained legacy PassKit code is an integration boundary, not exercised v2 Apple Pay. Merchant setup, entitlements, supported device, PSP and airline payment/order reconciliation remain required.
- **Fulfilment:** simulated, no ticket issued. No live order, real charge or publication occurred.
- **Personal travel memory:** separately opt-in; structured route/date/confirmed choice history, provenance-labelled searches/demo bookings, observed and AI preferences with exact evidence, corrections and lock/unlock, suppression/restoration, pause, export, activity deletion, history clearing and complete profile erasure. No child ages, names, raw messages/images, sensitive traits or payment data enter this memory.
- **Analytics:** opted-in native events are observed prototype activity; synthetic history is labelled and filtered separately. Aggregate proposals are hypotheses and have a configurable minimum sample threshold.

## Observed dashboard confirmation

The native demo confirmation reached the real dashboard after an end-to-end test identified and fixed a queued legacy screen alias (`results` → canonical `itinerary`). Existing event IDs were retained and retry deduplication preserved. The recorded prototype confirmation total was 19550c with selected extras of 4800c. Session-level event captures remain local; the public repository includes redacted app and dashboard screenshots. See [recorded journey](screenshots/dashboard-v2-recorded-journey.png) and [confirmation timeline](screenshots/dashboard-v2-native-confirmation.png). These amounts are simulated selections, not revenue.

## Deliverable checks

`PegasusTripFit-Source.zip` and `PegasusTripFit-iOS-Simulator.zip` are generated by `scripts/package-deliverables.py`. ZIP integrity and credential-pattern checks passed; the archives exclude server `.env`, databases, dependencies, caches, signing material and developer-local files. The simulator archive preserves executable permissions and includes installation instructions. It is not a physical-device IPA.

The final analytics result uses a facts-bound observation catalogue computed from metric records. The model selects an allowed observation and writes the hypothesis, proposed change and experiment. Validation requires the metric IDs supporting that observation and exact numeric evidence. The final live request passed on its first attempt in2,180ms; it selected repeat visits during baggage configuration, backed by `friction.baggage.revisits` (value3,sample3,denominator6). See [final insight check](../backend/evidence/final-insight-verification.json).
