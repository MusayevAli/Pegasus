// Fictional adult-only structured facts in a fresh in-memory store. Never uses customer profiles or capability output.
import 'dotenv/config';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {PersonalizationStore,learnTravelPreferences} from '../src/personalization.js';
const store=new Store(':memory:');
try{
 const {profile}=new PersonalizationStore(store).create();
 profile.facts=[15,18,21].map(day=>({id:randomUUID(),kind:'confirmed_search',provenance:'sample_search',occurredAt:new Date().toISOString(),origin:'SAW',destination:'BER',departureDate:`2026-11-${day}`,maximumStops:0,seatPreference:'aisle',baggagePreference:'cabin'}));
 const result=await learnTravelPreferences(profile);
 const evidence={verifiedAt:new Date().toISOString(),inputProvenance:'three fictional adult-only structured sample-search facts; fresh in-memory profile, no customer data',factCount:profile.facts.length,learning:result.learning,preferences:result.preferences};
 writeFileSync('evidence/live-personalization-results.json',JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence,null,2));if(result.learning.source!=='openai')process.exitCode=2;
}finally{store.close();}
