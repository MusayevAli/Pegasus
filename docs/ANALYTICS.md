# Analytics contract and metric definitions

The executable ingestion schema is `backend/src/events.ts`; dashboard types are in `shared/analytics.ts`. The native emitter is `ios/App/Analytics.swift`.

## Events and privacy

The current wire envelope contains `eventId`, `occurredAt`, `sessionId`, `journeyId`, `screen`, `step`, `name`, `schemaVersion: 2`, `dataSource`, `componentId`, `sequence`, `appVersion`, and strict allowlisted `properties`. Journey and session IDs are pseudonymous UUIDs. Screen and event names are enumerations. Property strings are short machine identifiers; airport codes, counts, prices, recommendation IDs/versions, request/model IDs and validation outcomes are permitted. No names, passport data, payment tokens, raw search text, notes, photos, keystrokes or recordings are accepted. Unknown fields fail the batch.

Native events queue in bounded local storage while offline. The client preserves IDs and sequence on relaunch, and decodes old queued event envelopes before uploading the v2 shape. The backend accepts legacy envelopes and normalizes both schemas to the existing SQLite layout. The one known legacy `previousScreen: results` alias is normalized to `itinerary`, so already queued native back-navigation events recover without losing IDs. Unknown screen names remain rejected. `eventId` remains the primary deduplication key; retrying the same batch never repeats its effects. In the normalized storage format, `flowId` means the v2 booking `journeyId`; the optional legacy property named `journeyId` is a catalogue identifier, not that UUID.

Analytics consent is optional. Opt-out cancels pending upload, clears the local queue and pseudonymous identity, and prevents new behavioural events. The ingestion store does not record HTTP headers/IP addresses. Access controls protect aggregate metrics and demo session timelines; admin tokens never enter the iOS bundle. Remote deployments still need an organisational retention policy and TLS.

Sources remain separate: `synthetic` is reproducible test history, `demo` is recorded prototype interaction, and `live` is explicitly selected live provenance. Public ingestion cannot create synthetic events or trusted `ticket_issued` outcomes. Live session timelines are excluded. A live source label is not evidence of actual airline fulfilment. Mixed-source views are visibly labelled and cannot request OpenAI insights.

## API and configuration

- `POST /api/analytics/events` accepts batches of up to 200 events, using the client access token where configured.
- `GET /api/analytics/metrics?provenance=synthetic|demo|live|all&days=7|30|90` returns typed metrics, rules, sessions and observation-window metadata.
- `POST /api/analytics/insights` uses the same source/date filters and admin authentication.
- `GET /api/sessions/:id` returns allowlisted demo/synthetic timelines only.
- Existing `/api/events`, `/api/analytics` and `/api/ai/insights` routes remain aliases.

`ANALYTICS_MIN_SAMPLE` defaults to 3 distinct journeys. `ABANDONMENT_MINUTES` defaults to 30. Native `Analytics.inactivitySeconds` controls active-time expiry and defaults to 30 seconds; `ACTIVE_TIME_THRESHOLD_SECONDS` describes that configured interval in dashboard metadata. Keep these client/server settings consistent if changing the default. `OPENAI_MODEL_TEXT`, `AI_TIMEOUT_MS`, and the server-only `OPENAI_API_KEY` control model inference.

## Timing and lifecycle

Each screen entry opens a stable `visitId`. Native monotonic system uptime produces incremental `foregroundMs` and `activeMs` checkpoints, so clock corrections cannot inflate a duration. Navigation and periodic checkpoints close the preceding interval; background time contributes neither duration. Active time expires after the configurable idle interval. Repeated visits are aggregated as separate visits within the same journey.

`beginLoading()` and `endLoading()` record separate `loading_duration.loadingMs` deltas by visit. Concurrent requests measure the union of their visible waiting intervals. Loading overlaps foreground time and is not added to it; it may also overlap active time. It is never interpreted as confusion. `screen_duration` and loading events require a visit ID. Active deltas cannot exceed foreground deltas.

The dashboard shows median and interpolated p90 active time per screen visit, visible median, total loading time, revisits, backtracking, errors and inferred exits. Completed/incomplete active-time comparisons require the configured number of distinct journeys in each cohort. Repeated visits from one journey cannot satisfy that threshold. Completion timing stops at the first confirmed completion event, excluding later confirmation-page dwell. Missing completion timing is an em dash, rather than a fabricated zero.

A journey is ongoing until the inactivity window expires. Abandonment is inferred from meaningful activity, not from background bookkeeping. An idle duration checkpoint with no active time cannot keep it alive. Meaningful activity after the threshold reopens the same journey and marks it resumed; it does not become a second started journey. Completed journeys stay completed. A screen exit means the final screen of an incomplete journey whose inactivity threshold has elapsed.

## Denominators and pricing semantics

- The observation cohort contains distinct source + journey pairs with a `search_submitted` event inside the selected time window. Repeated searches in the same journey count once. Starting a new native booking creates a new journey.
- The ordered funnel is search → flight selected → configuration → review → payment → confirmation. Merely viewing results does not count as flight selection. A later required stage implies its prerequisites; optional bags/seats/meals fold into configuration.
- Each funnel percentage uses the previous required stage's reached-journey denominator. A drop-off is `denominator - reached`; ongoing journeys remain distinct from inferred abandoned journeys. Furthest-stage ongoing/abandoned counts are displayed alongside the window.
- Revisits are visit count minus distinct journeys visiting the screen. Back events are attributed to the screen left (`previousScreen`). Errors include validation, checkout failure and failed payment outcomes.
- Recommendation pairs are source + journey + stable recommendation ID + version. Acceptance is accepted pairs divided by actually visible pairs. Generated cards alone do not contribute an impression. Repeated rendering/acceptance does not multiply counts. Dismissal, application and removal are separate lifecycle counts; removal requires an application.
- Retention requires an explicit retained event and a final applied state after ordered apply/remove transitions. At-checkout retention counts pairs in journeys reaching checkout; confirmation retention additionally requires completed booking. Missing retention is never inferred from application alone. Distinct visible journeys determine sample adequacy, even when the pair denominator is larger due to revisions.
- Selected extras value is the latest `extrasMinor` per started journey, including incomplete ones. It is selection intent, not realised revenue. Revenue requires trusted `ticket_issued.totalMinor`; the delivered demo has zero real revenue.
- Gap cards distinguish event count from affected journeys. Limited sample inventory is not evidence of real airline demand. The component map shows semantic component events, not a pixel heatmap or recording.

## Evidence-linked AI

Every exported metric record has an ID, code-computed value/unit, distinct-journey sample size, denominator, observation start/end, source and cohort label. Completion timing uses completed journeys with recorded timing as its sample. Recommendation denominators are visible pairs while sample sizes are distinct visible journeys.

OpenAI receives only aggregate metric records meeting the configured threshold, the selected source and observation window. Code narrows the scope to a sampled error/backtrack signal, then a gap signal, or the booking funnel; it does not let unrelated post-confirmation dwell dominate a pre-booking experiment. It receives no sessions, names, notes or photos. Code also builds a small catalogue of factual observations from positive metric records and maps each statement to its required supporting IDs. The model selects an observation verbatim; the response schema limits that field to the catalogue and the validator requires its supporting IDs. The model writes the uncertain hypothesis, proposed change and experiment. The Responses API uses strict Structured Outputs whose metric references are enums of the exact supplied IDs, with `observation`, `evidenceMetricIds`, `hypothesis`, `proposedChange`, `suggestedExperiment`, `sampleAdequacy` and structured `evidenceNumbers`.

The backend rejects unknown/duplicate metric references, omitted or duplicate numerical evidence, changed values/sample sizes/denominators, incorrect adequacy, unsupported observations or missing supporting IDs, malformed/incomplete output and numerical claims embedded in prose. A simple schema pattern excludes digits and percent signs; the domain guard also excludes spelled quantities. A bounded repair may retry one validation failure with the same aggregates and a safe failure code or offending quantity word; provider errors and refusals fall back immediately. Quantitative facts are rendered from the validated metric records. Proposed changes remain hypotheses; sufficient sample for this display is not statistical proof or causal uplift. Long dwell alone does not establish confusion.

The dashboard links each model hypothesis to its exact metrics, sample sizes, denominators and frozen observation window. Source/date/token changes cancel pending generation and invalidate old drafts; changed metric values do the same. Failed generation keeps existing measured evidence. Missing credentials, insufficient data and invalid output visibly report unavailable/insufficient states; rules-based proposals remain explicitly rules-based.

## Reproducible seed

Run `npm run seed` in `backend`. Stable SHA-derived IDs make repeat seeding idempotent; UTC event times are anchored two days before initial seeding. A fresh seeded database has:

| Metric | Expected value |
| --- | ---: |
| Started journeys | 12 |
| Demo completed bookings / real issued tickets | 6 / 0 |
| Completion rate | 50% |
| Median foreground completion | 162,500 ms |
| Median active completion / p90 active completion | 111,250 / 116,250 ms |
| Errors | 3 |
| Selected extras / realised revenue | €906 / €0 |
| Ongoing / inferred abandoned / resumed | 0 / 6 / 0 |
| Funnel reached | 12 → 9 → 9 → 6 → 6 → 6 |
| No-result journeys / baggage back actions | 3 / 3 |
| Accepted / visible recommendation pairs | 6 / 9 |
| Retained at checkout / confirmation | 6 / 6 |
| Retained keep-allowance pairs | 3 |

These are fixtures, not Pegasus customer performance. Old seed events naturally leave the selected date window. Use a fresh `DB_PATH` for a new demonstration rather than relabelling old fixtures as observed activity.

## Verification

`backend/test/analytics-v2.test.ts` covers schema migration/deduplication/privacy, idle abandonment/resumption, active p90/loading/revisits, actual selection vs results views, unique visible recommendation/version pairs, configurable threshold, out-of-order retention transitions, and aggregate-only strict AI validation. Mock provider tests explicitly distinguish validation tests from live OpenAI evidence. See `dashboard/VERIFICATION.md` for actual browser checks and screenshots.
