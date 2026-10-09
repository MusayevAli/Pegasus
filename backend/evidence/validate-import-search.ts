// Local, deterministic confirmation step using extracted synthetic fixture facts.
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {localInstant} from '../src/v2/inventory.js';
import type {TripImport,SearchIntent,SearchResponse} from '../../shared/booking-v2.js';
const inputs=JSON.parse(readFileSync('evidence/live-trip-import-results.json','utf8')).results as Array<{inputName:string;status:number;result:TripImport}>;
const base:SearchIntent={revision:1,originAirport:'SAW',destinationAirports:[],tripType:'one_way',outboundDate:null,returnDate:null,dateWindow:null,durationNights:null,adults:1,childAges:[],budgetMinor:null,budgetScope:null,currency:'EUR',checkedBags:0,baggageScope:null,baggageDirection:null,noOvernight:true,maxConnections:null,departureAfter:null,arrivalDeadline:null,keepTogether:false,vegetarian:false,noAlcohol:false,meals:false,lockedFields:[],unresolved:[],incomingFlight:null};
const evidence=[];
for(const input of inputs){
 assert.equal(input.status,200);const extracted=input.result;const intent=structuredClone(base);intent.revision=extracted.revision;intent.outboundDate=extracted.localDate;
 if(extracted.kind==='event'){
  assert.ok(extracted.localDate&&extracted.localTime&&extracted.timeZone);
  const [hour,minute]=extracted.localTime.split(':').map(Number);
  const eventAt=localInstant(extracted.localDate,hour!,minute!,extracted.timeZone);
  intent.arrivalDeadline=new Date(eventAt.getTime()-180*60000).toISOString(); // Fictional QA user explicitly selects a 3-hour planning buffer.
  intent.destinationAirports=extracted.airportCandidates;
 }else{
  assert.ok(extracted.incomingFlight);assert.equal(extracted.incomingFlight.confirmed,false);
  intent.incomingFlight={...extracted.incomingFlight,confirmed:true};
  intent.originAirport=extracted.incomingFlight.arrivalAirport;intent.destinationAirports=['SAW'];
 }
 const response=await fetch('http://127.0.0.1:3002/api/v2/flights/search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({intent})});
 const result=await response.json() as SearchResponse;assert.equal(response.status,200);assert.ok(result.offers.length);
 for(const offer of result.offers){const outward=offer.itinerary.segments.filter(s=>s.direction==='outbound');assert.equal(outward[0]!.origin.code,intent.originAirport);assert.ok(intent.destinationAirports.includes(outward.at(-1)!.destination.code));if(intent.arrivalDeadline)assert.ok(Date.parse(outward.at(-1)!.arrivalAt)<=Date.parse(intent.arrivalDeadline));if(intent.incomingFlight){assert.ok(Date.parse(outward[0]!.departureAt)-Date.parse(intent.incomingFlight.arrivalAt)>=(intent.incomingFlight.minimumConnectionMinutes+45)*60000);assert.equal(offer.priceScope,'onward_party');}}
 evidence.push({inputName:input.inputName,requestId:extracted.requestId,confirmedIntent:intent,totalMatches:result.totalMatches,firstOffer:result.offers[0],checks:'date, destination, airport-local event deadline or same-airport connection buffer, and onward price scope passed'});
}
writeFileSync('evidence/live-import-search-results.json',JSON.stringify({verifiedAt:new Date().toISOString(),provenance:'fictional fixture extraction with explicit synthetic QA confirmation',cases:evidence},null,2));
console.log(JSON.stringify(evidence.map(v=>({inputName:v.inputName,requestId:v.requestId,totalMatches:v.totalMatches,checks:v.checks})),null,2));
