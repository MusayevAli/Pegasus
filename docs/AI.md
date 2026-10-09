# AI in booking v2

The native v2 flow uses genuine server-side OpenAI extraction for typed search, packing photos and trip screenshots. AI interprets the supplied input; the backend searches the explicitly chosen live Pegasus source or deterministic sample catalogue. Sample prices are calculated by code; live flight prices are preserved from the provider, with unknown extras left unpriced. Model output cannot create inventory, reserve seats, charge money or issue tickets.

## Configuration and request status

Set `OPENAI_API_KEY` only in `backend/.env` or a server secret manager. Keep an existing `.env`; do not overwrite it with the example. Keys never belong in Swift, plist, dashboard bundles, evidence or analytics.

`OPENAI_MODEL_TEXT` and `OPENAI_MODEL_VISION` fall back to `OPENAI_MODEL`, then `gpt-4.1-mini`. The verified live requests used `gpt-4.1-mini`. `AI_TIMEOUT_MS` defaults to 20000. The official SDK uses Responses `responses.parse`, strict `zodTextFormat`, `store:false` and no automatic SDK transport retries. See the [official Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs).

`GET /api/v2/capabilities` reports `liveAI`, the text/vision models, sample inventory, demo payments and simulated fulfilment independently. `liveAI:true` reports configuration; only a validated individual `source:"openai"` result proves that request succeeded. App routes require the configured `APP_ACCESS_TOKEN` Bearer token.

## Routes and behavior

Exact types live in [booking-v2.ts](../shared/booking-v2.ts); [BACKEND-V2.md](BACKEND-V2.md) covers the deterministic routes.

| Route | Input and result |
| --- | --- |
| `POST /api/v2/ai/search-intent` | `{revision,text,context:{currentDate,locale,timeZone},currentIntent}` → structured `SearchIntent`, summary, model, request ID and latency. Missing origin, child age, year or budget/baggage scope remains an explicit clarification. Locked current fields must retain their values and locks. |
| `POST /api/v2/ai/packing` | `{revision,imageBase64,mimeType}` → actual visible items with category, label, approximate `visibleCount` or null, confidence and uncertainty. Categories: clothes, laptop, gifts, sports, liquids, bag. |
| `POST /api/v2/ai/trip-import` | The image request plus device context → event or incoming-flight facts, exact airport candidates, local date/time, year, time zone, unresolved fields and suggested buffer. Incoming flights remain unconfirmed. Dates/time zones are validated; the user confirms the planning buffer, whose ground-travel assumptions remain unverified. |
| `POST /api/v2/ai/compare` | `{revision,intent,offerIds:[id,id]}` → both offers recomputed for the same party/needs, factual comparison rows and a short qualitative AI explanation. Outbound/return times use each airport’s IANA zone. No numerical claims appear in the model explanation; the table owns those facts. |
| `POST /api/v2/search/alternatives` | `{intent}` → up to three real computed candidates, exact before/after constraint changes and optional AI explanations restricted to those IDs. Locked constraints remain intact; applying a change requires a user choice. |
| `POST /api/analytics/insights?provenance=synthetic&days=30` | Admin route. Receives server-computed aggregates internally, then returns evidence-grounded observations, hypotheses and proposed experiments. The model selects a factual observation from server-computed allowed statements and must include its required metric IDs. It writes the uncertain hypothesis, proposed change and experiment. Metric IDs are constrained to the exact snapshot; evidence numbers/sample sizes/denominators must match exactly. |

Search text is capped at 2000 characters; image payloads, item arrays and strings are bounded. User text and embedded image instructions are untrusted. AI does not infer preferences from identity or establish weight, dimensions, compliance, entry rules or connection protection. A photo alone cannot establish baggage fit: deterministic packing options require confirmed per-traveller, per-direction measurements and do not pool allowances. The same bag travelling over connecting segments is not additional capacity.

## Failure, privacy and confirmation

V2 extraction has **no canned AI fallback**. Missing credentials, refusal, incomplete/invalid output, timeout or cancellation produces an explicit unavailable/error state; manual search remains available. Stale revisions and changed locked fields are rejected. Clients cancel superseded requests and validate response revisions before applying them.

Comparison can still show its computed factual table with `explanationSource:"unavailable"`. Alternatives can retain computed candidates with `explanationSource:"deterministic"`. Neither substitutes a fabricated AI answer. Analytics may return explicit rules-based findings when live interpretation is unavailable or evidence is insufficient; its source and diagnostics identify that state. It uses at most one bounded repair for invalid model evidence, without weakening validation.

The backend does not persist raw search text, images or extracted personal document content in analytics. Booking AI audits retain only feature, model, request ID, latency, time and outcome. Screenshot extraction excludes names, contacts, booking references and unrelated personal fields. Required guest traveller names belong to the order record and are not sent to AI. Inputs are sent to the configured OpenAI service for the requested interpretation.

## Executed verification

The following files in `backend/evidence` record genuine successful requests, not sample responses presented as live:

- `live-search-results.json`: three adult-only synthetic prompts produced distinct validated routes, dates, scoped needs and offer IDs.
- `live-packing-results.json`: two inspected public object photos produced different inventories: packed clothes/bags versus one laptop.
- `live-trip-import-results.json` and `live-import-search-results.json`: two hash-verified fictional event images and one fictional incoming-flight image were extracted, confirmed in the QA harness and used in valid sample searches. Barcelona and Berlin retain their different local dates/times; LGW arrival retains its exact airport and offset.
- `live-comparison-results.json`: a real qualitative comparison and three computed alternatives, all re-searched successfully. `live-alternatives-results.json` records the final successful qualitative AI explanations for those exact candidates, with no numerical claims.
- `live-insight-results.json` and `final-insight-verification.json`: the final facts-bound contract passed a live call on its first attempt. The chosen repeat-visit observation references the required baggage revisit metric exactly; the model supplies its own uncertain hypothesis and proposed experiment.

The final backend suite passed 76 tests and TypeScript build, including mocked provider rejection paths, quote expiry/repricing, baggage scope, local-time DST and idempotent demo checkout. Live calls prove the AI path works; they do not prove airline availability or production payment readiness. See [VERIFICATION.md](VERIFICATION.md) for the broader app verification.

## Legacy compatibility

Legacy `/api/ai/status`, `/api/ai/plan`, `/api/ai/guidance` and `/api/ai/packing` remain for the earlier flow and tests. Their explicitly labelled local phrase matcher and empty photo fallback are legacy behavior; the v2 native search/photo flow uses the `/api/v2` contracts above. Legacy `/api/ai/insights` delegates to the current aggregate insights implementation.
