# Dashboard verification

## Current verification — 8 October 2026 PDT / 9 October UTC

Used the running local TypeScript backend on `127.0.0.1:3001`, Vite on `127.0.0.1:5173`, and Chrome through the computer-use browser interface. These are browser checks of the actual application, not static mockups.

- Backend `npm run build` and dashboard `npm run build` passed.
- `node --import tsx --test test/backend.test.ts test/analytics-v2.test.ts` passed **31/31** before the final observation-catalogue regression test; the final complete backend suite passed **58/58**, including **15/15** analytics tests. The local HTTP test initially could not bind within the sandbox; the approved loopback run passed. Fifteen new analytics tests cover v2 schema migration/deduplication/privacy, active p90/loading/revisits, abandonment/resumption, actual flight selection, recommendation version denominators, distinct-journey thresholds, retention ordering, numerical evidence validation, bounded AI repair, facts-bound observation selection and the legacy results/back-navigation alias. Mocked provider tests are not claimed as live inference.
- Overview showed **12 started journeys, 6 demo completions, 0 real tickets, 50% completion, 3 errors, €906 selected extras and €0 realised revenue**. Active completion median/p90 were **1m 51s / 1m 56s**, rounded from the fixture values of 111,250 / 116,250 ms.
- Funnel displayed **12 → 9 → 9 → 6 → 6 → 6**, previous-stage denominators, 0 ongoing and 6 inferred abandoned journeys, plus observation dates and the 30-minute inference rule.
- Time & friction displayed active median/p90, visible median, loading total, revisits, errors, backtracking and inferred exits. The active and backtracking sort controls were exercised. Missing completed/incomplete cohorts displayed em dashes. Synthetic history correctly had zero loading events; this is not fabricated model latency.
- Recommendation table showed **6 accepted / 9 visible pairs**, and separately **6 retained at checkout / 6 at confirmation**. Stable ID/version × journey denominator wording, removed counts and keep-allowance outcomes were visible.
- Completed-session filter reduced the synthetic table to six rows. A session opened its actual 22 allowlisted events, with ordered timing/selection/recommendation/checkout/completion events. Session visible time includes later confirmation dwell; overview completion time stops at completion as documented.
- Fixed a real native queue blocker: older V2 back events emitted `previousScreen: results`; ingestion now normalizes this one known alias to canonical `itinerary` without rewriting event IDs. The native store also corrects future emissions.
- Switching from Synthetic to Recorded cleared the synthetic summary and previous AI status. Live source showed zero journeys, insufficient evidence, and a disabled generation action. The dashboard never treated the seeded data as observed customer performance.
- Cancelling generation returned an explicit cancelled status, re-enabled generation and preserved all evidence cards. Clicking Baggage back actions opened Time & friction with the supporting baggage row highlighted.
- At 390 × 844, overview cards and controls fit the viewport and navigation retained accessible labels. The temporary viewport override was reset to desktop.
- Saved updated overview, friction, recommendation, session and mobile screenshots in `../docs/screenshots/dashboard-v2-*.png`.

## Native booking observed in the dashboard

After the legacy back-navigation alias was normalized, the actual queued V2 journey uploaded without rewritten IDs. The browser's Recorded prototype view showed the completed journey, then its expanded confirmation event:

- Journey `6AB1E330-6EC3-49BD-B8D2-73C6192165CC`; session `987F4699-C67B-485B-8972-061A0F193E60`.
- `demo_booking_completed` at `2026-10-09T03:21:18Z`, event `9986FCAA-3F3D-43A2-B321-A0FC735F08C9`.
- `totalMinor: 19550`, `extrasMinor: 4800`, order `bb156f6a-040c-4a75-9e21-2439edd823b9`. This is a demo completion, not ticket issuance or revenue.
- The captured journey had 151 events, 291,139 ms active / 580,574 ms visible time (including subsequent screen dwell), and 11,600 ms separately measured loading. These are the whole observed journey, including search editing/comparison and later navigation; they are not a benchmark against the earlier app.

Evidence: `../docs/screenshots/dashboard-v2-recorded-journey.png`, and `../docs/screenshots/dashboard-v2-native-confirmation.png`. No passenger names, raw text, images or payment data appear in this analytics evidence.

## Live model verification

The initial browser **Generate AI experiments** action made a real backend request and correctly showed unavailable/fallback when output failed validation. Direct provider diagnostics established that earlier failures included numerical prose and invented metric IDs. Metric-ID enums and bounded repair addressed those failures. Inspection then caught an unsupported prose claim despite exact structured numbers. The final contract therefore makes observation an enum of code-computed factual statements, each requiring its supporting metric IDs; OpenAI writes the uncertain hypothesis, proposed change and experiment. The dashboard labels the measured observation separately.

The **final current-source live check passed on its first attempt** at `2026-10-09T03:34:15Z`: source `openai`, validation `valid`, model `gpt-4.1-mini`, latency **2,180 ms**, request `b09c8394-ebcd-4eb3-a3a5-236bdb43cbe3`, provider `resp_069914fa0f29ca9f016ac860b5eaf087d18e96127248e1964e`. It selected the allowed observation “Repeat visits were recorded during baggage configuration.” and linked exactly `friction.baggage.revisits`, value **3**, distinct-journey sample **3**, visit denominator **6**. Its hypothesis is explicitly uncertain; the proposed change and experiment contain no numeric claims or invented uplift. This is live OpenAI inference over synthetic aggregate evidence, not observed customer performance.

Exact current responses are saved in `../backend/evidence/live-insight-results.json` and `../backend/evidence/final-insight-verification.json`. The final dashboard production build passed. A subsequent unlocked browser pass on the current server completed a real Generate AI experiments action: OpenAI validation was valid, latency rounded to 6 seconds, and the selected factual observation linked baggage revisits value 3 / sample 3 / denominator 6. The visible source remained Synthetic demo data. Screenshot `../docs/screenshots/dashboard-v2-ai-live.png` captures the result. Clicking its metric opened the highlighted baggage row. The actual recorded native confirmation was recaptured with totalMinor 19550.

Focused accessibility QA verified named navigation/actions, modal Tab wrapping and Escape dismissal, plus session Escape dismissal. Secondary text contrast and small evidence labels were improved, with reduced-motion support. A screen-reader-only table label initially expanded the mobile document width; positioning its containing block fixed this. At a 390px viewport the final document width is 390px, while wide tables scroll inside their panels. The temporary viewport was reset. This is focused QA, not a claim of a full WCAG audit.

## Scope and limits

This report describes the dashboard and analytics verification only. Native Simulator evidence, new booking-flow completion and other provider/vision/payment checks are covered by the project verification report. Earlier October 3 browser screenshots remain historical and are not substituted for this verification. JSON export download persistence and a forced browser timeout were not independently reverified in this pass; guards are implemented and were inspected. No live airline tickets, live customer performance, or payment revenue are claimed.
