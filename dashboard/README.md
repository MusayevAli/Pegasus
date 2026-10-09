# TripFit airline dashboard

React + TypeScript with Vite. All values come from the TripFit backend; the UI never substitutes fake fallback metrics.

## Run locally

Start and seed the backend first (see the project README). Then:

```sh
cd dashboard
npm ci
npm run dev
```

Open http://127.0.0.1:5173. Development and preview servers bind to loopback by default. Vite forwards `/api` to http://127.0.0.1:3001. `npm run build` checks TypeScript and creates `dist/`. Serve production assets behind the same origin as the API (or configure a reverse proxy); Vite's development proxy does not run in a production static build.

## Use

- **Synthetic demo data** is the default and remains separate from **Recorded prototype** interactions.
- Complete actions in the native app with backend analytics enabled, then select **Recorded prototype**. Metrics refresh every five seconds.
- The period filter supports 7, 30 and 90 days. Export report downloads exactly the current filtered aggregate response as JSON.
- All seven sections are functional. Improvement evidence links open the corresponding metric view and highlight the supporting row. Session search and status filters work together; a session opens its allowlisted event timeline.
- For protected deployments, select **Private analytics → Access** and enter the server's analytics token. The token is held in session storage, never embedded in the frontend bundle. Close the tab to clear that browser session. Use HTTPS and server access controls for remote hosting.
- Empty cohorts remain empty. Errors retain the last successful snapshot and recover automatically; filter changes clear the prior source's data.

## Interpretation

Funnel bars show share of started flows; row percentages use the backend's eligible previous-step denominator. Active and abandoned counts stay distinct. Optional extras fold into configuration. Selected extras value is not realised revenue. Demo completions and actual provider-confirmed tickets remain separate. Recommendation impressions require visibility events. Evidence cards label explanations as hypotheses and suppress insights below the backend's minimum cohort.

The semantic component map aggregates IDs and counts. It is not a recording or replay. Session exploration excludes live production sessions.

## OpenAI experiment drafts

In **Improvement lab**, select **Generate AI experiments**. The authenticated `POST /api/analytics/insights` route receives the selected source and date range. The backend sends OpenAI only aggregate metric records with IDs, sample sizes, denominators and observation windows. Returned hypotheses must reference supplied IDs and reproduce exact evidence numbers. Invalid references/numbers are rejected before the UI sees a draft.

Model observations, proposed changes and experiments appear with links to their verified metrics, separate from rules-based cards. The frozen window and source stay visible. Below the minimum distinct-journey threshold, or for mixed sources, generation is disabled. Repeated recommendation versions cannot inflate that minimum.

Missing credentials and provider/validation failures visibly report AI unavailable and retain measured evidence. Cancellation, timeout/retry, source/date/token guards and evidence-snapshot matching prevent stale drafts from replacing current data. Credentials remain server-side; no OpenAI key is shipped in this dashboard.

## Timing and denominators

The active-time table includes median/p90, visible median, separately measured loading, revisits, errors, backtracking and inferred exits. The footer shows the observation window and abandonment threshold. Ongoing and resumed journeys remain explicit. Recommendation acceptance uses distinct visible ID/version × journey pairs; removal and retention at checkout/confirmation are separate. Cohort adequacy uses distinct journeys, not repeat visits or recommendation versions. See `../docs/ANALYTICS.md` for precise definitions.

Factual observations are selected from code-computed statements linked to required metric IDs. OpenAI writes the uncertain hypothesis, proposed change and experiment; it cannot rewrite the observation or its numerical evidence. The dashboard labels this distinction.
