# TripFit backend, data and integration contract

## Run locally

Use Node 22.13 or newer (verified with Node 25.9.0). From `backend`:

```sh
npm ci
cp .env.example .env
npm run build
npm test
npm run seed
npm start
```

The backend listens at `http://127.0.0.1:3001`. It seeds a fresh database on start, unless `SEED_ON_START=false`. Data persists in `backend/data/tripfit.sqlite`; `.env`, data and node_modules are ignored. Seed inserts are deterministic and idempotent. To make an isolated demo use another `DB_PATH`; deleting a database is not part of startup or reset.

No credentials are required. Inventory, flight combinations and monetary amounts are illustrative demo data, including when OpenAI is configured. No payment is processed and no real ticket is issued.

The dashboard proxies `/api` to port 3001. An iOS simulator uses `http://127.0.0.1:3001`. A physical device uses the Mac's LAN address. For LAN binding, set `HOST=0.0.0.0`, choose separate `APP_ACCESS_TOKEN` and `ANALYTICS_ADMIN_TOKEN`, and configure the iOS client with only the app token. The dashboard asks for its admin token and keeps it in session storage. Use HTTPS behind a reverse proxy outside the local development network. Do not expose an unauthenticated loopback instance through a tunnel: configure the tokens before proxying it.

## API

All endpoints accept/return JSON. Money is integer EUR cents. Invalid schemas return 400, deterministic rule conflicts 409, unauthorised access 401, and unconfigured live payment 503. Body size is capped at 6 MB. Error responses never echo raw notes, photos or tokens. There are no payload, request-body or IP logs.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/health` | Public runtime/demo state |
| POST | `/api/events` | App token when configured; accept up to 200 versioned events |
| GET | `/api/analytics?provenance=synthetic&days=30` | Admin token; all aggregate dashboard views |
| GET | `/api/sessions/:sessionUUID` | Admin token; consented prototype/synthetic timeline only |
| GET | `/api/ai/status` | App token; configured model and supported AI features |
| POST | `/api/ai/plan` | App token; personalised summary, explicit needs and clarification choices |
| POST | `/api/ai/guidance` | App token; earlier typed-card compatibility route |
| POST | `/api/ai/packing` | App token; visual item candidates, labels, confidence and questions for confirmation |
| POST | `/api/ai/insights?provenance=synthetic&days=30` | Admin token; optional explanations of rule-supported aggregate findings |
| POST | `/api/quotes` | App token; deterministic, expiring server quote |
| POST | `/api/payments` | App token; idempotent demo completion or explicit live-provider-unavailable error |

Filters allow provenance `synthetic`, `demo`, `live`, `all`, and days `7`, `30`, `90`. Exact dashboard response types are in `shared/analytics.ts`. Bearer tokens are sent in the `Authorization` header. Non-loopback server startup fails unless both tokens exist. The application does not ship a remotely deployable user/account identity system; production access should use organisation authentication and per-user roles rather than distributing shared demo tokens.

### Quote and payment example

```json
{
  "journeyID": "family",
  "adults": 2,
  "children": 1,
  "roundTrip": true,
  "revision": 3,
  "selection": {
    "bundle": "family",
    "extras": [{"passengerID":"adult-1","segmentID":"family-in","productID":"peg-checked20"}],
    "seats": [{"passengerID":"child-1","segmentID":"family-in","seatID":"4C"}],
    "meals": [{"passengerID":"child-1","segmentID":"family-in","productID":"peg-meal-child"}]
  }
}
```

The quote response contains `id`, `expiresAt`, `revision`, `baseMinor`, `extrasMinor`, `totalMinor`, `currency`, itemised `items`, and `inventorySource: "demo"`. Quotes expire in 15 minutes. The server derives totals from its catalogue, never a submitted client amount. Payment revalidates the stored selection against the current catalogue.

```json
{"quoteID":"<server-quote-uuid>","idempotencyKey":"<persisted-uuid>","mode":"demo"}
```

The success state is `completed_demo`, authorization `simulated`, capture `not_charged`, issuance `not_issued`, and a `DEMO-` reference. The response explicitly states that there was no charge or real ticket. Repeating a key with a different request is rejected. Repeating a successful quote, even with a different key, returns the original demo result. For demo tests, `simulateOutcome` may be `cancelled` or `failed`; neither produces a booking reference. A failed/cancelled attempt can retry with a fresh key. Quote and payment records are stored without payment tokens.

### Payment and airline boundary

`payments.ts` defines separate `PaymentProvider.authorize`, `.capture`, `.voidAuthorization` and `AirlineProvider.issue` methods. The HTTPS gateway adapters implement JSON calls to `/authorizations`, `/captures`, `/voids` and `/tickets`, with independent idempotency keys and response validation. These are documented integration contracts, not a claim that a particular processor or airline is connected. An issued ticket requires the airline adapter's explicit `issued` response and nonempty ticket IDs; a wallet authorization is not issuance.

The demo quote pipeline rejects `mode: "apple_pay"` even if a token is supplied, because charging illustrative inventory would be incorrect. Before enabling live processing, supply authoritative live inventory and quotes, implement/verify the processor gateway and airline gateway contracts, add durable orchestration/reconciliation and refund recovery, and configure PassKit merchant/capabilities on the native client. Live payment and airline issuance are intentionally disabled here. Never enable a real charge merely by adding an OpenAI key.

## OpenAI

The official `openai` JavaScript SDK uses Responses `responses.parse`, with Zod strict Structured Outputs through `zodTextFormat`. The current guide was inspected during implementation: https://developers.openai.com/api/docs/guides/structured-outputs . `OPENAI_MODEL` is configurable (default `gpt-4.1-mini`). All calls run on the backend. `OPENAI_API_KEY` is never sent to the iOS app/dashboard or persisted in a quote. Requests set `store:false`, use an 8-second default timeout and no automatic retries that would hold up booking.

`GET /api/ai/status` returns `{configured,model,features}` under the app token. Features are `trip_plan`, `packing_vision`, and `aggregate_insights`. A configured client is not proof of a successful request: each plan or packing result declares `source:"openai"` only after a valid model response; otherwise it declares `source:"local"` and `model:null`.

`POST /api/ai/plan` accepts revision, a maximum 600-character note, known journey ID, adult/child types, segment IDs and allowlisted existing preference chips. It returns a personalised summary, nullable explicit need flags, packing categories, bounded clarification questions and a notice. A successful AI summary is preserved rather than replaced with a fixed template. Unstated flags remain null; existing preference chips are context, not new intent. Checked-bag and meal flags apply to every traveller on every supported flight, so incomplete scope requires clarification. False means explicitly declined. The native client uses confirmed needs to calculate catalogue-priced options and requires a deliberate action before changing selections.

The plan route rejects unknown fields, stale revisions, incomplete output, duplicate clarification IDs and invalid choice values. Missing credentials, refusal, timeout, rate limits and invalid responses use a clearly labelled limited local phrase matcher that respects explicit negations and never infers preferences from identity. The UI should tell users not to put documents, payment details or identifying information in notes. Notes are treated as untrusted data and are not written to analytics. Full request/response examples and limits are in [AI.md](AI.md).

The earlier `/api/ai/guidance` route remains available for compatibility. It validates product and passenger/segment scope and renders reviewed factual card explanations; its legacy local source label is `demo`. The native personalised-plan flow uses `/api/ai/plan`, whose honest source labels are `openai` and `local`.

Packing input is base64 JPEG/PNG/WebP, at most approximately 4 MB, sent transiently only for the requested vision call. It is never saved in analytics or the database. A successful response preserves the model's summary, item labels, confidence and confirmation questions; each item has an allowlisted clothes/laptop/gifts/sports/liquids category. The backward-compatible `candidates` array is derived from those validated items. Users must confirm/correct every candidate; a photo cannot reliably measure weight, dimensions or baggage compliance. Missing credentials or images, refusal, invalid output, timeout, rate limits and API failures return `source:"local"`, `model:null`, empty candidates/items/questions, and an explicit notice that the photo was not analysed. The manual checklist remains available. No default clothes/laptop detections or sample analysis are presented as results from the selected image.

Aggregate insight prompts contain only already-validated rule findings and evidence counts, with no session timelines or individual data. Optional AI explanations are labelled hypotheses and retain the unchanged supporting metric cards. Unknown insight IDs are rejected. Rule insights remain available without credentials.

## Verification performed

`npm run build` passed. Backend tests cover deterministic family bundle savings, included-item non-duplication, passenger/segment/direction scopes, child-seat eligibility and unavailable seats, external-airline purchase rejection, baggage upgrade differences, expired quote handling, cancellation/failure and duplicate payment retries, missing AI credentials, stale/invalid AI scopes, analytics ID deduplication, incremental timing, optional-step denominators, active versus abandoned flows, true recommendation impressions/reversals, privacy suppression, seed totals and HTTP authentication.

The 27-test backend suite passed, including mocked-provider coverage of strict Responses requests, preservation of personalised plan and vision output, negation/scope handling, refusal and stale-response fallback, no invented image detections, and protected AI status/plan routes. Mocked-provider tests do not prove live account access. Live OpenAI calls, processor authorizations/captures, live ticket issuance and device Apple Pay were not exercised because credentials/integrations were not supplied.
