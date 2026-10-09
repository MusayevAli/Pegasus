# 90-second demonstration

Use the running native Xcode app, local backend and dashboard. Begin with **Live Pegasus** selected. For the complete in-app purchase rehearsal, switch explicitly to **Demo booking**. Choose a date inside the catalogue's rolling 30-day window; the dates below were verified on 8 October 2026. Load a public packing photo into the simulator library before presenting. A working server key is required for the live AI portions.

| Time | Show and say |
|---|---|
| 0–10s | **Search.** “We turn a traveller's real plans into an editable booking. This is a native SwiftUI iPhone app.” |
| 10–25s | Enter a fresh description: **One adult from SAW to Barcelona on October 24, 2026, one way, direct, no checked bag, under 500 euros total.** Submit. “A real model extracts these fields. The search engine then finds flights that match them.” Point to editable chips, date, route and provider party fare. Open a flight to show the official Pegasus continuation. |
| 25–45s | Switch to **Demo booking**, search again and choose a sample flight. Enter fictional guest names. Expand **Bags → Show what you're packing**, choose the prepared photo and **Identify visible items**. “The model sees this photo, and I can correct its item list. It cannot weigh a bag.” Confirm items and enter an actual demonstration measurement, for example one bag,23kg,70×45×30cm. Confirm measurements and compare options. |
| 45–55s | Choose an eligible bag option and point to the changed pinned total and Undo. “The catalogue sets eligibility and price. A paid change needs my tap.” |
| 55–65s | Show the rehearsed no-match case: an implausibly low budget produces at most three actual alternative itineraries and exact proposed changes. “It cannot silently relax a locked requirement.” For a continuous booking demonstration, run this budget case before selecting the flight; the talking point still belongs here. |
| 65–78s | **Review trip**, show itemised total, acknowledge review, tap **Complete demo booking**. “This saves a demo trip. No money is charged and no ticket is issued.” |
| 78–90s | Dashboard: select **Recorded prototype interactions** and show the new confirmation in its journey. Switch explicitly to **Synthetic history** for the adequately sized rehearsal cohort and generate/show the evidence-linked insight. “These are measured events. AI proposes an experiment from aggregate evidence; a hypothesis is not proof of improvement.” |

The table is a rehearsed talk track, not a measured ninety-second usability result. Live response time and typing add variation. Do not describe synthetic sessions as customers or a configured AI key as proof of a successful request. The Developer diagnostics request ID and `backend/evidence` provide verification.

## Personalization talking point

“TripFit can remember the travel choices I confirm. Here is what it thinks it knows, why it thinks that, and how confident it is. I can correct it, stop collection, or export and erase my data. A search is interest, not proof that I visited somewhere.”

Open the profile icon, enable travel memory, complete two distinct confirmed searches, then show the learned preferences and supporting routes. Use **Your data & collection** to demonstrate the separate consent switch and JSON export. Never present demo bookings as real travel history.

## Additional demonstrations

- **Different request:** SAW→AYT,20October2026,after10:00,direct,€80total produces different actual flight cards. A Berlin return18–21October2026 with one bag both ways produces different dates, segment scope and prices.
- **Edit/lock:** edit or remove a chip; the search updates. Lock the budget, then request an incompatible journey: no alternative may exceed that budget.
- **Photo contrast:** suitcase/clothes versus a laptop photo. Show genuinely different item categories, uncertainty and editable counts. Existing allowance can be retained; extra return needs are entered separately.
- **Screenshot to trip:** import the fictional Barcelona conference or Berlin concert fixture, inspect airport/date/year/time zone, set the airport-arrival buffer and confirm. Ground travel is the traveller's estimate.
- **Incoming flight:** import the fictional British Airways JFK→LGW itinerary. Confirm local arrival and a connection buffer, then search onward Pegasus flights. The incoming flight is independently booked; the quote covers onward flights only. There is no invented Pegasus US flight or combined protected ticket.
- **Comparison:** select two cards, compare identical passenger/extras scope and airport-local schedules. The model explanation is qualitative; factual rows and prices come from backend offers.
- **AI unavailable:** use an unavailable test backend/model in rehearsal. Manual search works; no canned answer is presented as AI.

## Judge questions

**What's new compared with Pegasus today?**
Pegasus already offers flight booking, bags/seats/meals, Trip Finder, an AI assistant and Global Connect. This concept integrates interpretation into actual search state, connects confirmed packing measurements to priced choices, and makes constraint changes explicit.

**What is actually live?**
The SwiftUI app and backend are running. OpenAI text, vision, comparison and aggregate insight calls were exercised successfully. Pegasus flight search also returns real provider flights, schedules and fares, with an official Pegasus booking continuation. In-app extras and checkout are the separate sample demonstration. There is no in-app real payment or ticket issuance.

**Why use AI?**
It interprets language and images. Search eligibility, local-time arithmetic, baggage fit and prices remain deterministic code.

**How is data handled?**
The submitted description or selected photo goes to the server's model request. Behavioural analytics excludes text, images, names, passport details and payment data, uses pseudonymous IDs and requires optional consent.
