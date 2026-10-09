# Integration status and external setup

The delivered v2 app combines **live AI, live read-only Pegasus search, separate sample booking, demo payment and simulated fulfilment**. These capabilities are independent; `/api/v2/providers` reports source-specific support. The older `/api/v2/capabilities` retains sample-booking catalogue metadata.

| Component | Verified now | Remaining external setup |
| --- | --- | --- |
| Native app | iOS simulator build with Xcode 26.3, typed v2 booking flow and authoritative backend quote/order path | Device signing, production accessibility/device QA and deployment |
| OpenAI | Genuine text, packing-vision, trip-import, comparison, alternatives and aggregate insight requests | Configure a server key/model/account/network for each deployment |
| Inventory | Actual anonymous Pegasus MCP availability and prices; separate sample catalogue through extras, seats and demo quote | NDC/partner access for live ancillary pricing, repricing, fare terms and orders |
| Checkout | Expiring quotes, current-price/availability checks, persistent idempotency and saved demo orders | Authorised PSP and airline fulfilment; no live charge or ticket was attempted |
| Analytics | Native events, durable offline queue, SQLite dedup, scoped metrics and evidence-validated AI hypotheses | Private HTTPS hosting, production identity, retention/deletion and operational controls |
| Travel eligibility | Exact airport identity, absolute connection timing and explicit `not_checked` entry requirements | Authoritative entry/transit rules for actual documents; AI is not that authority |

## OpenAI and API boundaries

`OPENAI_API_KEY` stays in `backend/.env` or a secret manager. `.env` is excluded from deliverables. Text and vision models use `OPENAI_MODEL_TEXT` / `OPENAI_MODEL_VISION`, falling back to `OPENAI_MODEL`, then `gpt-4.1-mini`. Verified requests used `gpt-4.1-mini`. Restart after environment changes. Never embed server credentials in the native client or dashboard.

The current app calls `/api/v2/ai/search-intent`, `/api/v2/ai/packing`, `/api/v2/ai/trip-import`, `/api/v2/ai/compare` and `/api/v2/search/alternatives`. The official Responses SDK uses strict Structured Outputs and actual image payloads. V2 extraction returns explicit errors when unavailable; it never presents canned output as AI. Manual search remains available. Computed comparison/alternative facts can remain visible with an explicit unavailable/deterministic explanation source. See [AI.md](AI.md) for exact behavior, model configuration and live evidence files.

All prices and eligibility come from the backend catalogue, not the model. The user confirms imported details and proposed changes. A photo cannot determine bag weight, dimensions or compliance; the deterministic packing comparison requires measurements and scopes them per traveller/direction.

## Airline providers and discovery

`backend/src/v2/providers.ts` supplies the working `SampleProvider` and an explicitly unsupported `PegasusNDCProvider` boundary. Search, alternatives and comparison accept an explicit `provider` selection: `pegasus_mcp` or `sample`. Live failures never silently switch to sample. `SAMPLE_START_DATE` can pin the sample window; otherwise it begins tomorrow. Fare names Light, Saver, Saver Plus and Comfort Flex have illustrative fixture benefits, not asserted live-route terms.

No authorised Pegasus NDC, MCP/BolBol or partner credentials were configured when checked. The [official NDC API page](https://devportal.flypgs.com/Api) and [FAQ](https://devportal.flypgs.com/Question) describe AirShopping, OfferPrice, ServiceList, SeatAvailability, OrderCreate and OrderChange. Integration requires business onboarding, issued test credentials, allowed server IPs, current authorised schemas/workflow mapping and certification. These are service names, not invented public REST routes. Search, reprice, extras, seats and fulfilment must use the same authorised source.

A read-only discovery of the [official Pegasus MCP endpoint](https://mcp.flypgs.com/) returned HTTP 200 for `initialize` and `tools/list`. The advertised tool names were `flight-search`, `pnr-search`, `best-deals` and `point-search`. The discovered `flight-search` schema declares anonymous read-only use, and actual flight searches subsequently succeeded without credentials. Recorded one-adult, two-adult return and connecting searches validate live schedules and provider party prices. No PNR/account/order tool was invoked. This proves live search, not authenticated account or booking access. The returned list did not advertise extras, seat selection, payment or order tools. Live flight cards contain only verified provider facts, with unprovided baggage/seats/quote fields null. Official search continuation is supported; live repricing, extras and checkout still need authorised provider integration.

The US-origin sample explicitly uses a non-Pegasus carrier at JFK and Pegasus onward at AMS. Independently booked incoming flights are context only, excluded from `onward_party` totals. IST and SAW are never interchangeable. Connection buffers and check-in assumptions are sample planning rules, not guarantees; through-baggage, connection protection and transit eligibility are not invented. Live Global Connect/Dohop integration needs authorised partner access and verified terms. See [PROVIDERS.md](PROVIDERS.md) for the detailed capability record.

## Demo checkout and retained PassKit integration

V2 `/api/v2/checkout` accepts only `paymentMode:"demo"`. It rechecks quote expiry, availability and price, persists an authoritative order, and supports cancellation/failure plus idempotent retry. Successful demo orders have `ticketIssued:false`, `fulfilmentStatus:"not_issued"` and no real charge.

The retained `ios/App/ApplePay.swift` is genuine legacy PassKit code: `PKPaymentButton`, `PKPaymentRequest`, capability checks, reconciled summary items and delegate cancellation/failure. It requires a server-validated **live** quote before showing the wallet. It is **not wired as the v2 payment processor**, and sample offers never enable it. Legacy `/api/payments` currently rejects `apple_pay` with `live_provider_unavailable`.

Live sandbox integration still requires an Apple Developer team, matching merchant ID/entitlements, payment-processing certificates, a supported device and sandbox account, an authorised PSP implementation and validated live airline quotes/orders. Legacy interfaces in `backend/src/payments.ts` distinguish authorization, capture, void and airline issuance; their generic adapter routes are boundaries, not completed Pegasus/PSP mappings. Wallet authorization alone is not a ticket. No provider secret, Apple merchant backend credential or PSP credential was configured for real processing during verification.

## Networking and deployment

The backend binds loopback by default. Non-loopback binding requires both `APP_ACCESS_TOKEN` and `ANALYTICS_ADMIN_TOKEN`, with separate device and dashboard access. Dashboard tokens stay in session storage rather than the bundle. Prototype device token preferences should become short-lived authenticated credentials stored in Keychain before production.

Use HTTPS for remote hosting and a reachable Mac hostname/local-network permission for physical-device development. Do not disable ATS globally. Production requires scoped identity, rate limits, restricted origins, retention/deletion and operational security review. The completed simulator build and demo checkout do not establish device Apple Pay or production airline certification.

References: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [Apple PassKit](https://developer.apple.com/documentation/passkit/offering-apple-pay-in-your-app), [Apple Pay sandbox testing](https://developer.apple.com/apple-pay/sandbox-testing/), [Pegasus Global Connect](https://pegasus.dohop.com/). The prototype catalogue remains illustrative even where public product names are used.
