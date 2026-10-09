// Synthetic QA examples created for the acceptance tests; no person's plans, name, child age or identifying data.
import {writeFileSync} from 'node:fs';
const base='http://127.0.0.1:3002';
const cases=[
 'Synthetic acceptance test, not an actual traveller: two adults, no children. Search SAW to BCN, departing 15 October 2026 and returning 22 October 2026. One checked bag for the whole party in both directions. No overnight travel. EUR 1200 total party budget.',
 'Synthetic acceptance test, not an actual traveller: one adult, no children. One-way SAW to AYT on 20 October 2026, no checked bags, direct flight only, departure after 10:00 local. EUR 80 total party budget.',
 'Synthetic acceptance test, not an actual traveller: one adult, no children. SAW to BER departing 18 October 2026 and returning 21 October 2026, one checked bag per traveller both ways, no overnight travel, EUR 500 total party budget.'
];
const evidence=[];
for(let i=0;i<cases.length;i++){
 const body={revision:i+1,text:cases[i],context:{currentDate:'2026-10-08',locale:'en-US',timeZone:'America/Los_Angeles'},currentIntent:null};
 const r=await fetch(base+'/api/v2/ai/search-intent',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const extraction=await r.json();
 if(!r.ok){evidence.push({case:i+1,aiStatus:r.status,error:extraction});continue;}
 const searched=await fetch(base+'/api/v2/flights/search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({intent:extraction.intent})});const result=await searched.json();
 evidence.push({case:i+1,input:cases[i],source:extraction.source,model:extraction.model,requestId:extraction.requestId,latencyMs:extraction.latencyMs,intent:extraction.intent,resultStatus:searched.status,totalMatches:result.totalMatches,firstOffers:result.offers?.slice(0,3).map(o=>({id:o.id,total:o.totalPrice,durationMinutes:o.itinerary.durationMinutes,segments:o.itinerary.segments.map(s=>({carrier:s.operatingCarrier,origin:s.origin.code,destination:s.destination.code,departureAt:s.departureAt,arrivalAt:s.arrivalAt}))}))});
}
writeFileSync('evidence/live-search-results.json',JSON.stringify({verifiedAt:new Date().toISOString(),inputProvenance:'synthetic adult-only QA cases',inventory:'sample',payments:'demo',cases:evidence},null,2));
console.log(JSON.stringify(evidence.map(e=>({case:e.case,source:e.source,requestId:e.requestId,latencyMs:e.latencyMs,matches:e.totalMatches,unresolved:e.intent?.unresolved,error:e.error,firstIds:e.firstOffers?.map(o=>o.id)})),null,2));
