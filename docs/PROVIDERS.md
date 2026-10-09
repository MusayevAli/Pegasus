# Provider status and authorised integration prerequisites

Verified during the October 2026 implementation. Credential checks report presence only; no secret values are printed or copied into artifacts.

| Capability | Current state |
| --- | --- |
| Server-side OpenAI | Configured; live text extraction and vision calls verified with synthetic requests/public object images |
| Flight inventory | Live read-only Pegasus MCP search, plus an explicitly separate sample provider with 2,700 dated flights |
| Payments | Demo only; no charge attempted |
| Ticket fulfilment | Simulated; every demo order has `ticketIssued:false` and `fulfilmentStatus:not_issued` |
| Pegasus NDC credentials | Not configured |
| Pegasus MCP/BolBol token | Not configured |
| Dohop/partner credentials | Not configured |
| Payment processor credentials | Not configured |
| Apple merchant backend credentials | Not configured; native merchant/device setup remains external |

`GET /api/v2/providers` is the source-specific capability catalogue. New clients explicitly choose `pegasus_mcp` for live search or `sample` for the booking demo. The `provider` field belongs to search/alternatives/comparison requests, outside the AI travel intent. Omitted provider retains legacy sample behavior. No live failure substitutes sample records. The older `/api/v2/capabilities` fields describe the sample booking engine and AI configuration; use `/providers` to choose inventory. Live AI, live search and payment/fulfilment are separate capabilities.

## Sample provider

`backend/src/v2/providers.ts` defines the provider boundary. The working `SampleProvider` supplies consistent catalogue, search, services and authoritative quote models; orders revalidate the same selected inventory and deterministic price engine. There are no LLM-generated flights. Sample schedules and prices are illustrative even where routes are plausible.

`SAMPLE_START_DATE=YYYY-MM-DD` optionally pins the catalogue's first date. Otherwise it begins tomorrow and covers 30 days. Search respects local route/date, party size, requested scoped baggage, budget, connections, overnight preference, departure time and arrival deadline. Return offers combine actual outbound and return records. Sold-out options are filtered. Itemised quotes expire after ten minutes and must be reviewed again if expired or repriced.

Public-facing sample fare names are Light, Saver, Saver Plus and Comfort Flex. Included benefits are expressly fixture conditions; they are not assertions about a live route-specific Pegasus offer. The model cannot create prices, product eligibility or bundle terms.

## Pegasus NDC

The [official API page](https://devportal.flypgs.com/Api) and [FAQ](https://devportal.flypgs.com/Question) describe AirShopping, OfferPrice, ServiceList, SeatAvailability, OrderCreate and OrderChange workflows. Those are service names, not guessed public REST routes.

The `PegasusNDCProvider` is an explicit unsupported boundary. Enabling it requires business onboarding, issued test credentials, allowed server IPs, current authorised request/response schemas, partner workflow mappings and live certification. No real shopping, order or fulfilment call was made. Connecting a provider must keep inventory source consistent through search, repricing, extras, seats, checkout and confirmation.

## Official Pegasus MCP live search

The [official MCP service](https://mcp.flypgs.com/) exposes `https://mcp.flypgs.com/mcp`. Discovery returned HTTP 200 for `initialize` and `tools/list`, advertising `flight-search`, `pnr-search`, `best-deals` and `point-search`. The actual `flight-search` schema explicitly declares `securitySchemes: noauth`, `readOnlyHint:true` and `destructiveHint:false`. Its arguments are origin, destination, departureDate, optional returnDate, adults, children, infants, nonStop, currency and locale. Full account services require BolBol authentication; the verified public flight-search tool does not.

`backend/src/v2/pegasus-mcp.ts` now performs real server-side protocol negotiation and invokes **only** `flight-search`. It uses an overall timeout, validates anonymous/read-only tool metadata, handles authentication/errors explicitly, and validates the actual structured response. It never invokes PNR, points, account or order tools. No credential is required or sent for this public path. If the provider later requires authorisation, the server stops with `provider_authentication_required`; it does not bypass that boundary.

Live calls on 9 October 2026 UTC returned:

- SAW→BCN on 24 October, one adult: two flights, provider-reported EUR 254.00 and EUR 240.00.
- The same outbound with two adults: EUR 508.00 and EUR 480.00, explicitly `passengers:2` / `adults:2`. BCN→SAW on 30 October returned separate party fares EUR 463.24 and EUR 454.88.
- AYT→BCN on 24 October: nine connecting results, including next-day connections across the Europe/Madrid daylight-saving transition.

These are actual provider responses recorded at the stated time, not promises of continuing availability. Evidence is in `backend/evidence/pegasus-mcp-discovery.json`, `pegasus-live-search.json`, `pegasus-live-roundtrip.json` and `pegasus-live-connecting.json`. The native HTTP harness also verified live search and comparison against the backend.

Party prices are preserved exactly; adult fares are never multiplied to invent group/child totals. Round-trip cards clearly show an indicative sum of provider-returned directional party fares. Actual currency is preserved without an invented conversion. No complete ancillary-inclusive total is claimed. Route/date/party/currency, chronological leg times, known airport time zones and official handoff parameters are validated. Departure time, arrival deadline, connections, overnight restriction and flight-price budget are filtered deterministically. Unknown airports/time zones or inconsistent times are rejected rather than guessed.

Flexible live searches run at most two destinations × three representative departure dates (start/middle/end), six queries total and two concurrently, under one overall 25-second default timeout. The response explicitly describes bounded coverage and any partial failures; it is not an exhaustive flexible-date fare calendar. Exact searches keep one flight-search call. Return dates derive separately for each departure when a duration was requested, and each offer keeps the correct provider continuation URL. Nearby-date alternatives expand one day on either side only when departure/date-window locks allow it; all other constraints are checked before an explicit change card is offered. Four deterministic mock tests cover these additions; the expansion itself was not sent to the live service during verification.

The tool does **not** supply flight numbers, baggage inclusions, seat counts, fare holds, ancillary pricing, quote/reprice, order or payment operations. Those fields remain null/unverified. `requestedExtrasPriced:false` and per-offer capabilities prevent sample services, quotes or demo checkout from being attached to live offers. A short server cache exists only for comparing the same search snapshot; it is not a price hold.

The supplied `bookingURL` is validated as an official HTTPS `web.flypgs.com/booking` search continuation with matching route/date/party. It opens a search on Pegasus; it does not reserve the highlighted flight. Final flight selection, fare terms, bags, seats and payment must be confirmed there. Live alternatives use actual returned candidates and explicit constraint changes; requested extras remain unpriced.

## Multi-airline and independent incoming flights

The separately selected US-origin sample uses an explicitly labelled KLM sample segment at JFK and Pegasus onward at AMS. It is never presented as a Pegasus-operated US flight. Separate-ticket examples state that connection protection is not supplied and show reclaim/recheck/security steps. Independently booked incoming flights are context only and are not charged in an onward quote, whose scope is `onward_party`.

Airport codes remain exact; IST and SAW are never interchangeable. Connection filtering checks absolute instants, identical transfer-airport code and configurable buffer plus check-in deadline. The buffer is a planning assumption, not a guarantee. Entry/transit requirements stay `not_checked`. Authorised Global Connect/Dohop access, verified provider terms and baggage mappings would be needed for live combined itineraries.

## Payment and Apple Pay prerequisites

Only the sample checkout accepts `paymentMode:demo`, persists an authoritative order and supports cancellation/failure and idempotent retries. No money or real airline order is created. Existing native PassKit and backend processor/airline interfaces are retained separately.

Real sandbox testing requires an Apple Developer team, matching merchant ID and entitlements, supported device/sandbox account, payment-processing certificates, an authorised PSP workflow, and validated live provider quotes/orders. PSP authorization, capture and ticket issuance must remain separate. A PSP token must not be forwarded into a Pegasus order service without its authorised integration contract.
