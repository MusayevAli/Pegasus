import { z } from 'zod';

export const eventNames = [
 'search_submitted','search_completed','results_shown','no_results','screen_viewed','screen_duration','loading_duration','step_completed',
 'preference_changed','filter_changed','offer_compared','offer_selected','connection_opened','baggage_changed','seat_changed','meal_changed',
 'validation_error','back_navigation','checkout_started','checkout_cancelled','checkout_failed','payment_outcome','demo_booking_completed','ticket_issued',
 'recommendation_generated','recommendation_visible','recommendation_expanded','recommendation_accepted','recommendation_dismissed','recommendation_applied','recommendation_reversed','recommendation_retained',
 'ai_request_started','ai_request_finished','trip_imported','comparison_opened','alternative_selected','quote_updated','journey_resumed',
] as const;
export const screens = ['search','itinerary','configuration','baggage','seats','meals','review','checkout','confirmation','trips','import','comparison'] as const;
const semantic = z.string().min(1).max(120).regex(/^[A-Za-z0-9_.:-]+$/);
const count = z.number().int().min(0).max(100_000_000);
export const propertiesSchema = z.object({
 journeyId:semantic.optional(),origin:z.string().regex(/^[A-Z]{3}$/).optional(),destination:z.string().regex(/^[A-Z]{3}$/).optional(),
 partySize:count.max(9).optional(),resultCount:count.optional(),code:semantic.optional(),direction:z.enum(['outbound','return','inbound']).optional(),
 productId:semantic.optional(),segmentId:semantic.optional(),passengerType:z.enum(['adult','child']).optional(),valueMinor:count.optional(),totalMinor:count.optional(),extrasMinor:count.optional(),
 foregroundMs:count.max(86_400_000).optional(),activeMs:count.max(86_400_000).optional(),loadingMs:count.max(86_400_000).optional(),
 visitId:semantic.optional(),recommendationId:semantic.optional(),recommendationVersion:count.optional(),recommendationType:z.enum(['baggage','meals','seating','bundle','connection','keep_allowance','alternative','flight_comparison']).optional(),
 choice:semantic.optional(),previousScreen:z.enum([...screens,'results']).transform(screen=>screen==='results'?'itinerary':screen).optional(),completed:z.boolean().optional(),revision:count.optional(),
 offerId:semantic.optional(),quoteId:semantic.optional(),orderId:semantic.optional(),requestId:semantic.optional(),modelId:semantic.optional(),
 validationOutcome:z.enum(['valid','invalid','failed','cancelled','unavailable','stale']).optional(),inventorySource:z.enum(['sample','live']).optional(),
 experimentId:semantic.optional(),experimentVariant:semantic.optional(),paymentStatus:z.enum(['started','authorized','captured','cancelled','failed','demo_completed']).optional(),
}).strict().superRefine((p,c)=>{
 if(p.activeMs!==undefined && (p.foregroundMs===undefined||p.activeMs>p.foregroundMs)) c.addIssue({code:'custom',message:'activeMs must not exceed foregroundMs'});
});
const normalizedSchema = z.object({
 id:z.string().uuid(),name:z.enum(eventNames),sessionId:z.string().uuid(),flowId:z.string().uuid(),screen:z.enum(screens),componentId:semantic,
 sequence:count,clientTimestamp:z.string().datetime({offset:true}),appVersion:z.string().regex(/^\d+\.\d+(\.\d+)?$/),
 schemaVersion:z.union([z.literal(1),z.literal(2)]),provenance:z.enum(['demo','live','synthetic']),properties:propertiesSchema,
}).strict();
const v2Schema = z.object({
 eventId:z.string().uuid(),occurredAt:z.string().datetime({offset:true}),sessionId:z.string().uuid(),journeyId:z.string().uuid(),
 screen:z.enum(screens),step:z.enum(['search','flight_selection','configuration','review','payment','confirmation','other']),
 name:z.enum(eventNames),schemaVersion:z.literal(2),dataSource:z.enum(['demo','live','synthetic']),
 componentId:semantic,sequence:count,appVersion:z.string().regex(/^\d+\.\d+(\.\d+)?$/),properties:propertiesSchema,
}).strict().transform(e=>({id:e.eventId,clientTimestamp:e.occurredAt,sessionId:e.sessionId,flowId:e.journeyId,screen:e.screen,name:e.name,schemaVersion:e.schemaVersion,provenance:e.dataSource,componentId:e.componentId,sequence:e.sequence,appVersion:e.appVersion,properties:e.properties}));
/** v1 remains accepted for already queued clients; v2 is normalized before persistence. */
export const eventSchema = z.union([normalizedSchema,v2Schema]).superRefine((e,c)=>{
 if(e.name==='screen_duration' && (!e.properties.visitId || e.properties.foregroundMs===undefined || e.properties.activeMs===undefined)) c.addIssue({code:'custom',message:'Duration requires visitId and both incremental timing deltas'});
 if(e.name==='loading_duration' && (!e.properties.visitId || e.properties.loadingMs===undefined)) c.addIssue({code:'custom',message:'Loading requires visitId and incremental loadingMs'});
 if(e.name.startsWith('recommendation_') && (!e.properties.recommendationId||!e.properties.recommendationType))c.addIssue({code:'custom',message:'Recommendation events require stable ID and type'});
});
export type Event = z.infer<typeof eventSchema>;
export type StoredEvent = Event & {serverReceivedAt:string};
