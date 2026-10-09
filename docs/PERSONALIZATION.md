# Personal travel memory

Personal travel memory powers “What we know about me.” It is a separate opt-in purpose from optional aggregate behavioural analytics. Enabling either setting does not enable the other. A profile starts empty; the app sends only structured travel facts the customer has confirmed after enabling collection. Existing device histories are not uploaded automatically.

## Scope and controls

A fact contains a UUID, confirmed-search or confirmed-trip kind, source provenance, observation timestamp, origin/destination airport codes, departure/optional return dates, and optional maximum stops, seat preference and baggage preference. Source provenance distinguishes `sample_search`, `live_search`, `demo_booking`, and `live_booking`. A demo booking is not ticket issuance. Search and booking provenance must match the fact kind.

The strict schema rejects raw prompts, emails, names, passenger information, passport data, images, payment data and unknown properties. No religion, health, ethnicity, politics, wealth, family status or other sensitive trait is inferred. Preferences never set a personalised price. The current preference keys are origin airport, destination airport, maximum stops, seat preference and baggage preference.

Customers can:

- Pause collection. New facts are rejected and no model call is made. Existing history, corrections and export remain available.
- Correct and lock a preference. A lock survives new facts and model learning. Unlocking allows a later explicit learning request to replace that value.
- Delete a preference. Its key is suppressed from later observed/model learning until the customer explicitly adds a correction for that key.
- Remove a history fact. Observed preferences are recomputed and prior model preferences are invalidated.
- Clear history. Facts and learned/observed preferences are removed; explicit user corrections remain. Delete the profile to remove those too.
- Export the structured profile. The export contains no capability token or credential.
- Delete the profile. All profile data is removed and its capability immediately stops working.

Storage is bounded to 200 facts per profile and 30 facts per ingestion request. Duplicate fact IDs are idempotent and do not overwrite existing records. The customer can remove a fact before adding a corrected replacement. Facts persist until removed or the profile is deleted; disabling collection alone does not erase history.

## Private access

`POST /api/personalization/profiles` requires the normal application access policy and the explicit body `{ "collectionEnabled": true }`. It returns an empty profile and a random 256-bit capability token. Native code keeps this token in Keychain, separately from the shared application token.

Every `/api/personalization/me` endpoint requires that unique capability as `Authorization: Bearer …`. A profile UUID, another profile's capability or the shared application token cannot authorize the profile. There is no endpoint that enumerates profiles or accepts an arbitrary target customer ID. SQLite stores only the capability's SHA-256 hash. Responses containing profiles or new capabilities use `Cache-Control: no-store`. A capability is a bearer secret; possession grants access to that profile, and deletion revokes it. Remote deployments require the existing token-gated server configuration and TLS.

The `personal_profiles` table is separate from analytics events. Personal facts are never copied into aggregate analytics or analytics session timelines. No names, raw text or photo data are retained by this service.

## How learning works

Code computes allowed preference candidates from observed values and their exact supporting fact IDs. Repeated facts may support a candidate; they are not independent people or statistical proof. `supported` currently means at least three supporting facts and at least 60% of the relevant facts for that key; other candidates are `tentative`. Direct customer corrections are `confirmed`. These are display categories, not calibrated probabilities.

Observed preferences work without AI. After a new confirmed fact, the opted-in native app can schedule learning, and the customer can request it using Update what you know. The server sends only the allowed structured facts and candidate catalogue to OpenAI. Structured Outputs restrict the response to exact candidate IDs, fact IDs and confidence categories. The model selects useful, non-conflicting candidates; it cannot invent a preference value, factual description, sensitive trait or numerical confidence. Code rejects unknown candidates, missing/extra/duplicate evidence, conflicting values for a key, or a confidence category inconsistent with the evidence. Locked and suppressed preference keys are excluded from the candidates.

The Responses API uses `store: false`, a bounded timeout and no automatic retry. Missing credentials, insufficient history or invalid provider output report an honest unavailable/insufficient state while retaining observed facts and corrections. No model call runs when collection is paused; `/me/learn` returns HTTP 200 with the unchanged profile and `learning.state: unavailable`, `source: none`. A profile-version check prevents an in-flight response from overwriting later consent changes, corrections, deletion or history clearing.

## API contract

Types are in `shared/personalization.ts`; executable validation and routes are in `backend/src/personalization.ts`.

| Method and path | Body / result |
| --- | --- |
| `POST /api/personalization/profiles` | `{collectionEnabled:true}` → `{capabilityToken, profile}` |
| `GET /api/personalization/me` | `TravelProfile` |
| `PATCH /api/personalization/me` | `{collectionEnabled:boolean}` → profile |
| `POST /api/personalization/me/facts` | `{facts:TravelFact[]}` → `{accepted,duplicates,profile}` |
| `POST /api/personalization/me/learn` | `{}` → profile, including `learning` status |
| `PUT /api/personalization/me/preferences/:key` | `{value:string\|number,locked:boolean}` → profile; lock defaults true |
| `DELETE /api/personalization/me/preferences/:key` | Suppress that preference key → profile |
| `DELETE /api/personalization/me/facts/:id` | Remove fact and invalidate dependent learning → profile |
| `DELETE /api/personalization/me/history` | Clear facts and non-user preferences → profile |
| `GET /api/personalization/me/export` | `{schemaVersion:1,exportedAt,profile}` |
| `DELETE /api/personalization/me` | Erase profile and revoke capability → HTTP 204 |

Learning status is `{state,source,message,model?,requestId?,latencyMs?}`. `source: openai` is returned only after real provider output passes all validation. A stale in-flight result returns HTTP 409 `profile_changed`; the client should refresh before retrying. Disabled ingestion returns 409 `collection_disabled`; full history returns 409 `history_limit`.

## Verification

Eight focused tests cover strict privacy/schema validation, capability isolation and hashed storage, evidence/confidence calculations, invented model outputs, paused/insufficient/missing-key states, locked corrections, API edit/delete/export/clear controls, and a consent change during an active model request. All pass. The complete backend suite passed 74 tests after integration, and TypeScript compilation passed. Mock provider tests are not claimed as live inference. Any live verification uses a separate in-memory profile with fictional travel facts and does not upload existing customer histories.

The final isolated live check passed with `source: openai`, `state: ready`, latency **4,776 ms**, request `46bb40fb-a384-4029-a119-3f2a44ef4d6c`. Five preferences were validated against three fictional structured facts in a fresh in-memory store. `backend/evidence/live-personalization-results.json` contains the safe result and diagnostics without a capability token. No existing customer history was read or uploaded.
