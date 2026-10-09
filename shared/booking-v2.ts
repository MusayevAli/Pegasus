// Wire contract for /api/v2. Dates YYYY-MM-DD; instants ISO8601 with offset. Prices integer EUR cents.
export interface Money { amountMinor:number; currency:string }
export interface Airport { code:string; name:string; city:string; country:string; timeZone:string }
export interface DeviceContext { currentDate:string; locale:string; timeZone:string }
export interface UnresolvedField { field:string; question:string; choices:string[] }
export interface SearchIntent {
 revision:number; originAirport:string|null; destinationAirports:string[];
 tripType:'one_way'|'round_trip'; outboundDate:string|null; returnDate:string|null;
 dateWindow:{start:string;end:string}|null; durationNights:number|null;
 adults:number; childAges:Array<number|null>;
 budgetMinor:number|null; budgetScope:'party'|'per_person'|null; currency:'EUR';
 checkedBags:number|null; baggageScope:'party'|'per_passenger'|null; baggageDirection:'outbound'|'return'|'both'|null;
 noOvernight:boolean; maxConnections:number|null; departureAfter:string|null; arrivalDeadline:string|null;
 keepTogether:boolean; vegetarian:boolean; noAlcohol:boolean; meals:boolean;
 lockedFields:string[]; unresolved:UnresolvedField[];
 incomingFlight:IncomingFlight|null;
}
export interface IncomingFlight { airline:string; flightNumber:string|null; arrivalAirport:string; arrivalAt:string; departureAirport:string|null; minimumConnectionMinutes:number; baggageReclaim:boolean; confirmed:boolean }
export interface FlightSegment { id:string; operatingCarrier:string; flightNumber:string|null; origin:Airport; destination:Airport; departureAt:string; arrivalAt:string; durationMinutes:number; direction:'outbound'|'return'; ticketGroup:string; checkedBaggage:{pieces:number;totalWeightKg:number;maxPieceWeightKg:number;maxLinearCm:number}|null; underseat:{weightKg:number;dimensionsCm:number[]}|null; independentlyBooked:boolean }
export interface Itinerary { id:string; segments:FlightSegment[]; durationMinutes:number; connectionMinutes:number[]; overnight:boolean; transferType:'direct'|'through_ticket'|'self_transfer'|'independent_incoming'|'provider_not_specified'; transferSteps:string[]; terms:string; entryRequirements:'not_checked' }
export interface FareBundle { id:string; name:'Light'|'Saver'|'Saver Plus'|'Comfort Flex'; pricePerPassengerSegmentMinor:number; checkedPieces:number; checkedWeightKg:number; cabinIncluded:boolean; standardSeatIncluded:boolean; mealIncluded:boolean; conditions:string }
export interface AncillaryProduct { id:string; type:'cabin'|'checked'|'meal'; name:string; priceMinor:number; weightKg:number|null; pieces:number|null; tags:string[]; childOnly:boolean; eligibleSegmentIds:string[] }
export interface Seat { id:string; row:number; column:string; available:boolean; extraLegroom:boolean; childAllowed:boolean; priceMinor:number }
export interface SeatMap { segmentId:string; seats:Seat[]; suggestedFamilySeats:string[]; familyAvailable:boolean }
export type InventoryProviderID='sample'|'pegasus_mcp';
export interface OfferCapabilities {ancillaries:boolean;seats:boolean;quote:boolean;checkout:boolean;externalBooking:boolean}
export interface InventoryProvider extends OfferCapabilities {id:InventoryProviderID;label:string;source:'sample'|'live';search:boolean;authenticationRequired:boolean;notice:string}
export interface ProvidersResponse {defaultProvider:InventoryProviderID;providers:InventoryProvider[]}
export interface FlightOffer { id:string; provider:InventoryProviderID; source:'sample'|'live'; itinerary:Itinerary; basePrice:Money|null; totalPrice:Money; extrasPrice:Money|null; priceScope:'party'|'onward_party'; partySize:number; bundleId:string|null; includedCheckedPieces:number|null; includedCheckedWeightKg:number|null; baggageSummary:string; requestedExtrasPriced:boolean; available:boolean; remainingSeats:number|null; expiresAt:string|null; requestFingerprint:string; notices:string[]; bookingURL:string|null; capabilities:OfferCapabilities }
export interface SearchResponse { revision:number; source:'sample'|'live'; offers:FlightOffer[]; totalMatches:number; unresolved:UnresolvedField[]; notice:string; searchedWindow:{start:string;end:string}; requestFingerprint:string }
export interface Capabilities { liveAI:boolean; textModel:string; visionModel:string; inventory:'sample'; payments:'demo'; fulfilment:'simulated'; sampleWindow:{start:string;end:string}; offerCount:number; routePairs:number; providerNotice:string }
export interface CatalogResponse { capabilities:Capabilities; airports:Airport[]; bundles:FareBundle[]; routes:Array<{origin:string;destination:string}> }
export interface AIExtraction { revision:number; source:'openai'; model:string; requestId:string; latencyMs:number; intent:SearchIntent; summary:string }
export interface TripImport { revision:number; source:'openai'; model:string; requestId:string; latencyMs:number; kind:'event'|'incoming_flight'|'unknown'; title:string|null; location:string|null; airportCandidates:string[]; localDate:string|null; localTime:string|null; year:number|null; timeZone:string|null; incomingFlight:IncomingFlight|null; unresolved:UnresolvedField[]; suggestedArrivalBufferMinutes:number; notice:string }
export interface PackingItem { id:string; category:'clothes'|'laptop'|'gifts'|'sports'|'liquids'|'bag'; label:string; visibleCount:number|null; confidence:'low'|'medium'|'high' }
export interface PackingAssessment { revision:number; source:'openai'; model:string; requestId:string; latencyMs:number; summary:string; items:PackingItem[]; uncertainties:string[]; requiresMeasurements:true }
export interface BagSelection { passengerId:string; segmentId:string; productId:string }
export interface SeatSelection { passengerId:string; segmentId:string; seatId:string }
export interface MealSelection { passengerId:string; segmentId:string; productId:string }
export interface BookingSelection { bundleId:string; bags:BagSelection[]; seats:SeatSelection[]; meals:MealSelection[] }
export interface QuoteItem { id:string; label:string; amountMinor:number; passengerId:string|null; segmentId:string|null }
export interface Quote { id:string; revision:number; source:'sample'; provider:'sample'; offerId:string; selection:BookingSelection; passengers:Array<{id:string;type:'adult'|'child';age:number|null}>; items:QuoteItem[]; basePrice:Money; extrasPrice:Money; total:Money; status:'valid'; expiresAt:string; priceScope:'party'|'onward_party'; notices:string[] }
export interface OfferServices { offerId:string; bundles:FareBundle[]; products:AncillaryProduct[]; seatMaps:SeatMap[]; passengers:Array<{id:string;type:'adult'|'child';age:number|null}>; defaultSelection:BookingSelection }
export interface Alternative { id:string; offer:FlightOffer; changes:Array<{field:string;from:string;to:string}>; intent:SearchIntent; explanation:string; requiresConfirmation:true }
export interface AlternativesResponse { revision:number; alternatives:Alternative[]; notice:string; explanationSource:'deterministic'|'openai'; model:string|null; requestId:string|null }
export interface ComparisonResponse { revision:number; offers:FlightOffer[]; differences:Array<{label:string;values:string[]}>; explanation:string|null; explanationSource:'openai'|'unavailable'; model:string|null; requestId:string|null; notice:string }
export interface PackingMeasurement { passengerId:string; direction:'outbound'|'return'; pieces:number; totalWeightKg:number; maxPieceWeightKg:number; maxLinearCm:number; dimensionsCm?:number[]|null }
export interface PackingOption { id:string; title:string; explanation:string; selection:BookingSelection; total:Money; differenceMinor:number; action:'keep'|'add_bag'|'bundle'; requiresConfirmation:true }
export interface PackingOptionsResponse { status:'needs_measurements'|'ready'|'unsupported'; questions:string[]; options:PackingOption[]; notice:string }
export interface Order { id:string; quoteId:string; reference:string; state:'confirmed_demo'|'cancelled'|'failed'; paymentStatus:'simulated'|'cancelled'|'failed'; fulfilmentStatus:'not_issued'; ticketIssued:false; total:Money; createdAt:string; itinerary:Itinerary; selection:BookingSelection; travellerNames:string[]; notice:string }
// App-token auth if configured. Error response {error,message,retryable?,requestId?}; AI failure HTTP503, NEVER canned v2 AI.
// GET /api/v2/capabilities -> Capabilities; GET /api/v2/catalog -> CatalogResponse
// POST /api/v2/ai/search-intent {revision,text,context:DeviceContext,currentIntent:SearchIntent|null} -> AIExtraction
// POST /api/v2/flights/search {intent:SearchIntent,provider?:InventoryProviderID} -> SearchResponse
// POST /api/v2/search/alternatives {intent:SearchIntent,provider?:InventoryProviderID} -> AlternativesResponse
// POST /api/v2/ai/trip-import {revision,imageBase64,mimeType,context:DeviceContext} -> TripImport
// POST /api/v2/ai/packing {revision,imageBase64,mimeType} -> PackingAssessment
// POST /api/v2/ai/compare {revision,intent:SearchIntent,offerIds:[string,string],provider?:InventoryProviderID} -> ComparisonResponse
// GET /api/v2/offers/:id/services?adults=2&childAges=7 -> OfferServices (comma separated child ages)
// POST /api/v2/quotes {revision,offerId,intent:SearchIntent,selection:BookingSelection|null} -> Quote
// POST /api/v2/offers/:id/packing-options {intent,selection:BookingSelection,measurements:PackingMeasurement[],items:PackingItem[]} -> PackingOptionsResponse
// POST /api/v2/checkout {quoteId,idempotencyKey,travellerNames:string[],paymentMode:'demo',simulateOutcome?:'success'|'cancelled'|'failed'} -> Order
// GET /api/v2/orders/:id -> Order

// GET /api/v2/providers -> ProvidersResponse. Omitted provider retains legacy sample behavior; new clients explicitly default to pegasus_mcp. Live search prices exclude unprovided ancillary pricing; only validated official bookingURL continuation is supported.
