/** Opt-in personal travel memory. Separate from aggregate analytics consent. */
export type PreferenceKey = 'originAirport' | 'destinationAirport' | 'maximumStops' | 'seatPreference' | 'baggagePreference';
export type PreferenceValue = string | number;
export interface TravelFact {
 id: string; kind: 'confirmed_search' | 'confirmed_trip'; occurredAt: string;
 provenance: 'sample_search' | 'live_search' | 'demo_booking' | 'live_booking';
 origin: string; destination: string; departureDate: string; returnDate?: string | null;
 maximumStops?: 0 | 1 | 2; seatPreference?: 'any' | 'window' | 'aisle';
 baggagePreference?: 'personal_item' | 'cabin' | 'checked';
}
export interface TravelPreference {
 id: string; key: PreferenceKey; value: PreferenceValue; label: string;
 confidence: 'tentative' | 'supported' | 'confirmed'; source: 'observed' | 'openai' | 'user';
 evidenceIds: string[]; locked: boolean; updatedAt: string;
}
export interface PersonalizationStatus {
 state: 'not_requested' | 'ready' | 'unavailable' | 'insufficient';
 source: 'none' | 'openai'; message: string;
 model?: string; requestId?: string; latencyMs?: number;
}
export interface TravelProfile {
 id: string; collectionEnabled: boolean; createdAt: string; updatedAt: string;
 facts: TravelFact[]; preferences: TravelPreference[]; suppressedPreferenceKeys: PreferenceKey[];
 learning: PersonalizationStatus;
}
export interface CreateTravelProfileResponse { capabilityToken: string; profile: TravelProfile }
export interface AddTravelFactsResponse { accepted: number; duplicates: number; profile: TravelProfile }
export interface TravelProfileExport { schemaVersion: 1; exportedAt: string; profile: TravelProfile }
