import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {createApp} from '../src/server.js';
import {once} from 'node:events';
import {normalizePegasusResponse,PegasusMCPProvider,rejectLiveOperation,providerCatalogue} from '../src/v2/pegasus-mcp.js';
import {fingerprint,violations} from '../src/v2/engine.js';
import {airportByCode,localInstant,localTime,localDate} from '../src/v2/inventory.js';
import type {SearchIntent} from '../../shared/booking-v2.js';
const load=(name:string)=>JSON.parse(readFileSync(new URL(`../evidence/pegasus-live-${name}.json`,import.meta.url),'utf8')).packet.result;
const intent:SearchIntent={revision:1,originAirport:'SAW',destinationAirports:['BCN'],tripType:'one_way',outboundDate:'2026-10-24',returnDate:null,dateWindow:null,durationNights:null,adults:1,childAges:[],budgetMinor:null,budgetScope:null,currency:'EUR',checkedBags:0,baggageScope:null,baggageDirection:null,noOvernight:false,maxConnections:null,departureAfter:null,arrivalDeadline:null,keepTogether:false,vegetarian:false,noAlcohol:false,meals:false,lockedFields:[],unresolved:[],incomingFlight:null};
const discovery={tools:[{name:'flight-search',annotations:{readOnlyHint:true},securitySchemes:[{type:'noauth'}]}]};
function fakeProvider(store:Store,response:unknown,calls:any[]=[]){return new PegasusMCPProvider(store,(async(url,options)=>{assert.equal(url,'https://mcp.flypgs.com/mcp');assert.equal(new Headers(options?.headers).has('Authorization'),false);const request=JSON.parse(String(options?.body));calls.push(request);const result=request.method==='initialize'?{protocolVersion:'2025-03-26'}:request.method==='tools/list'?discovery:typeof response==='function'?response(request.params.arguments):response;return new Response(JSON.stringify({jsonrpc:'2.0',id:request.id,result}),{status:200,headers:{'Content-Type':'application/json'}});}) as typeof fetch);}
test('actual anonymous provider records normalize live prices and preserve unknown services',()=>{
 const r=normalizePegasusResponse(load('search'),intent);assert.equal(r.source,'live');assert.equal(r.totalMatches,2);assert.deepEqual(r.offers.map(o=>o.totalPrice.amountMinor),[24000,25400]);
 for(const o of r.offers){assert.equal(o.provider,'pegasus_mcp');assert.match(o.id,/^live-pegasus-/);assert.equal(o.basePrice,null);assert.equal(o.extrasPrice,null);assert.equal(o.remainingSeats,null);assert.equal(o.expiresAt,null);assert.equal(o.bundleId,null);assert.equal(o.itinerary.segments[0]!.flightNumber,null);assert.equal(o.itinerary.segments[0]!.checkedBaggage,null);assert.equal(o.requestedExtrasPriced,false);assert.equal(o.capabilities.checkout,false);assert.equal(o.capabilities.externalBooking,true);assert.match(o.bookingURL!,/^https:\/\/web\.flypgs\.com\/booking/);}
});
test('actual two-adult return fares are summed once, not multiplied or turned into quotes',()=>{
 const i={...intent,adults:2,tripType:'round_trip' as const,returnDate:'2026-10-30'};const r=normalizePegasusResponse(load('roundtrip'),i);assert.equal(r.totalMatches,4);assert.deepEqual(r.offers.map(o=>o.totalPrice.amountMinor),[93488,94324,96288,97124]);assert.ok(r.offers.every(o=>o.partySize===2&&o.itinerary.segments.length===2&&!o.capabilities.quote));assert.ok(r.offers[0]!.notices.some(n=>n.includes('sums')));
});
test('actual connecting records preserve local times, overnight dates and DST transition',()=>{
 const i={...intent,originAirport:'AYT'};const all=normalizePegasusResponse(load('connecting'),i);assert.equal(all.totalMatches,9);assert.equal(all.offers.filter(o=>o.itinerary.overnight).length,4);const daytime=normalizePegasusResponse(load('connecting'),{...i,noOvernight:true});assert.equal(daytime.totalMatches,5);assert.ok(daytime.offers.every(o=>o.itinerary.transferType==='provider_not_specified'));
 const nextDay=all.offers.find(o=>o.itinerary.segments[0]!.departureAt==='2026-10-24T20:40:00.000Z')!;assert.equal(nextDay.itinerary.segments[1]!.arrivalAt,'2026-10-25T10:45:00.000Z');assert.equal(nextDay.itinerary.connectionMinutes[0],540);
});
test('live route date party and official handoff identity are validated',()=>{
 const raw=load('search');assert.throws(()=>normalizePegasusResponse(raw,{...intent,adults:2}),/could not be verified|does not match/);assert.throws(()=>normalizePegasusResponse(raw,{...intent,outboundDate:'2026-10-25'}),/different route or date/);
 for(const url of ['https://evil.example/booking','http://web.flypgs.com/booking','https://web.flypgs.com/booking?redirect=https://evil.example']){const bad=structuredClone(raw);bad._meta.bookingUrl=url;assert.throws(()=>normalizePegasusResponse(bad,intent));}
 const bad=structuredClone(raw);bad.structuredContent.direct[0].outbound.legs[0].arrivalTime='22:00';bad.structuredContent.direct=bad.structuredContent.direct.slice(0,1);assert.throws(()=>normalizePegasusResponse(bad,intent),/could not be verified/);
});
test('live filtering does not claim unpriced baggage or extras meet budget',()=>{
 const i={...intent,budgetMinor:24500,budgetScope:'party' as const,checkedBags:1,baggageScope:'party' as const,baggageDirection:'outbound' as const,meals:true,keepTogether:true};const r=normalizePegasusResponse(load('search'),i);assert.equal(r.totalMatches,1);assert.equal(r.offers[0]!.requestedExtrasPriced,false);assert.match(r.offers[0]!.baggageSummary,/not supplied/);assert.ok(r.offers[0]!.notices.some(n=>n.includes('complete trip total is unknown')));
 const raw=load('search');raw.structuredContent.direct.forEach((f:any)=>f.currency='TRY');assert.equal(normalizePegasusResponse(raw,intent).offers[0]!.totalPrice.currency,'TRY');assert.throws(()=>normalizePegasusResponse(raw,i),/different currency/);
});
test('live provider only invokes documented noauth flight search and keeps source snapshots isolated',async()=>{
 const store=new Store(':memory:'),calls:any[]=[];const provider=fakeProvider(store,load('search'),calls);const r=await provider.search(intent);assert.deepEqual(calls.map(c=>c.method),['initialize','tools/list','tools/call']);assert.equal(calls[2].params.name,'flight-search');assert.equal(calls[2].params.arguments.adults,1);assert.equal(provider.cached(r.offers[0]!.id,intent).source,'live');assert.throws(()=>provider.cached(r.offers[0]!.id,{...intent,adults:2}),/different search/);assert.equal(r.requestFingerprint,fingerprint(intent));store.db.prepare('UPDATE v2_live_offers SET cache_expires_at=0').run();assert.throws(()=>provider.cached(r.offers[0]!.id,intent),/Refresh live search/);store.close();
});
test('live authentication and transport failures never substitute sample records',async()=>{
 const store=new Store(':memory:');const auth=new PegasusMCPProvider(store,(async()=>new Response('',{status:401})) as typeof fetch);await assert.rejects(()=>auth.search(intent),/requires authorised access/);const down=new PegasusMCPProvider(store,(async()=>{throw new Error('offline');}) as typeof fetch);await assert.rejects(()=>down.search(intent),/temporarily unavailable/);assert.throws(()=>rejectLiveOperation('live-pegasus-abc'),/does not expose/);assert.doesNotThrow(()=>rejectLiveOperation('sample-SAW-BCN'));assert.equal(providerCatalogue().defaultProvider,'pegasus_mcp');store.close();
});
test('live no-match alternatives preserve real IDs, exact constraints and locks',async()=>{
 const store=new Store(':memory:');const provider=fakeProvider(store,load('search'));const low={...intent,budgetMinor:100,budgetScope:'party' as const};const result=await provider.alternatives(low);assert.equal(result.length,2);for(const a of result){assert.equal(a.offer.source,'live');assert.deepEqual(a.changes.map(c=>c.field),['budgetMinor']);assert.equal(Number(a.changes[0]!.to),a.offer.totalPrice.amountMinor);assert.equal(provider.cached(a.offer.id,a.intent).source,'live');}assert.deepEqual(await provider.alternatives({...low,lockedFields:['budgetMinor']}),[]);store.close();
});


test('live round-trip filters use full party total and deterministic outbound local/absolute times',()=>{
 const i={...intent,adults:2,tripType:'round_trip' as const,returnDate:'2026-10-30'};const raw=load('roundtrip');
 assert.deepEqual(normalizePegasusResponse(raw,{...i,departureAfter:'11:00'}).offers.map(o=>o.totalPrice.amountMinor),[93488,94324]);
 assert.deepEqual(normalizePegasusResponse(raw,{...i,arrivalDeadline:'2026-10-24T12:00:00Z'}).offers.map(o=>o.totalPrice.amountMinor),[96288,97124]);
 assert.equal(normalizePegasusResponse(raw,{...i,budgetMinor:94000,budgetScope:'party'}).totalMatches,1);
 assert.equal(normalizePegasusResponse(raw,{...i,budgetMinor:47000,budgetScope:'per_person'}).totalMatches,1);
 assert.equal(normalizePegasusResponse(raw,{...i,budgetMinor:47000,budgetScope:'party'}).totalMatches,0);
 const overnight=load('connecting');overnight.structuredContent.connecting=[overnight.structuredContent.connecting.at(-1)];overnight.structuredContent.connecting[0].outbound.legs[0].departureTime='20:00';overnight.structuredContent.connecting[0].outbound.legs[0].arrivalTime='21:25';
 assert.equal(normalizePegasusResponse(overnight,{...intent,originAirport:'AYT'}).offers[0]!.itinerary.overnight,true);
 assert.equal(normalizePegasusResponse(overnight,{...intent,originAirport:'AYT',noOvernight:true}).totalMatches,0);
});
test('HTTP live IDs cannot reach sample extras quotes or mixed comparison',async()=>{
 const store=new Store(':memory:'),server=createApp(store).listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();assert.ok(address&&typeof address!=='string');const base=`http://127.0.0.1:${address.port}`;
 const post=async(path:string,body:unknown)=>fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 try{assert.equal((await fetch(base+'/api/v2/providers')).status,200);assert.equal((await fetch(base+'/api/v2/offers/live-pegasus-test/services?adults=1')).status,503);assert.equal((await post('/api/v2/quotes',{revision:1,offerId:'live-pegasus-test',intent,selection:null})).status,503);assert.equal((await post('/api/v2/offers/live-pegasus-test/packing-options',{intent,selection:{bundleId:'light',bags:[],seats:[],meals:[]},measurements:[],items:[]})).status,503);assert.equal((await post('/api/v2/ai/compare',{revision:1,intent,provider:'pegasus_mcp',offerIds:['live-pegasus-test','sample-any']})).status,400);}
 finally{server.close();await once(server,'close');store.close();}
});

// Synthetic provider packets exercise expansion deterministically; no network or current clock dependency.
function packetFor(args:any){
 const raw=load('search'),base=structuredClone(raw.structuredContent.direct[0]);
 const fare=(origin:string,destination:string,day:string,price:number)=>{const start=localInstant(day,10,10,airportByCode(origin).timeZone),end=new Date(+start+220*60000);return {...structuredClone(base),price,currency:args.currency,adults:args.adults,children:args.children,infants:0,passengers:args.adults+args.children,outbound:{date:day,legs:[{origin,destination,departureTime:'10:10',arrivalTime:localTime(end.toISOString(),airportByCode(destination).timeZone),duration:'3h 40m'}]}};};
 raw.structuredContent={searchParams:{origin:args.origin,destination:args.destination,departureDate:args.departureDate,returnDate:args.returnDate??null,isRoundTrip:!!args.returnDate},direct:[fare(args.origin,args.destination,args.departureDate,args.departureDate==='2026-10-24'?240:200)],connecting:[],returnDirect:args.returnDate?[fare(args.destination,args.origin,args.returnDate,100)]:[],totalFound:args.returnDate?2:1};
 const url=new URL('https://web.flypgs.com/booking');for(const [key,value]of Object.entries({departurePort:args.origin,arrivalPort:args.destination,departureDate:args.departureDate,...args.returnDate?{returnDate:args.returnDate}:{},adultCount:args.adults,childCount:args.children,infantCount:0,currency:args.currency,language:'en'}))url.searchParams.set(key,String(value));raw._meta.bookingUrl=url.toString();return raw;
}
test('bounded live flexible search queries two destinations and three representative dates with correct handoffs',async()=>{
 const store=new Store(':memory:'),calls:any[]=[],provider=fakeProvider(store,packetFor,calls),flex={...intent,outboundDate:null,dateWindow:{start:'2026-10-24',end:'2026-10-30'},destinationAirports:['BCN','BER','AYT'],tripType:'round_trip' as const,durationNights:4,adults:2};
 const result=await provider.search(flex),queries=calls.filter(c=>c.method==='tools/call').map(c=>c.params.arguments);
 assert.equal(queries.length,6);assert.deepEqual([...new Set(queries.map(q=>q.destination))],['BCN','BER']);assert.deepEqual([...new Set(queries.map(q=>q.departureDate))],['2026-10-24','2026-10-27','2026-10-30']);assert.equal(result.offers.length,6);assert.match(result.notice,/Bounded live search.*two destinations and three representative dates/);
 for(const o of result.offers){assert.equal(o.requestFingerprint,fingerprint(flex));assert.equal(provider.cached(o.id,flex).id,o.id);assert.equal(violations(o,flex).length,0);const url=new URL(o.bookingURL!),out=o.itinerary.segments[0]!,back=o.itinerary.segments[1]!;assert.equal(url.searchParams.get('departureDate'),localDate(out.departureAt,out.origin.timeZone));assert.equal(url.searchParams.get('returnDate'),localDate(back.departureAt,back.origin.timeZone));assert.equal(url.searchParams.get('arrivalPort'),out.destination.code);assert.equal(url.searchParams.get('adultCount'),'2');assert.equal(o.partySize,2);assert.equal(o.totalPrice.currency,'EUR');assert.ok([30000,34000].includes(o.totalPrice.amountMinor));assert.equal(o.requestedExtrasPriced,false);}
 store.close();
});
test('live expansion has concurrency two, discloses partial failures and preserves arrival deadlines',async()=>{
 const store=new Store(':memory:');let active=0,peak=0,queries=0;
 const provider=new PegasusMCPProvider(store,(async(_url,options)=>{const request=JSON.parse(String(options?.body));active++;peak=Math.max(peak,active);await new Promise(r=>setTimeout(r,2));active--;if(request.method==='tools/call'){queries++;if(request.params.arguments.destination==='BER')return new Response('',{status:503});}return new Response(JSON.stringify({jsonrpc:'2.0',id:request.id,result:request.method==='initialize'?{}:request.method==='tools/list'?discovery:packetFor(request.params.arguments)}));}) as typeof fetch);
 const flex={...intent,outboundDate:null,dateWindow:{start:'2026-10-24',end:'2026-10-26'},destinationAirports:['BCN','BER'],arrivalDeadline:'2026-10-24T20:00:00Z'};
 const result=await provider.search(flex);assert.equal(queries,6);assert.equal(peak,2);assert.equal(result.offers.length,1);assert.equal(violations(result.offers[0]!,flex).length,0);assert.match(result.notice,/partial results/);store.close();
});
test('nearby live alternatives change only listed unlocked fields and preserve per-query booking and snapshot identity',async()=>{
 const store=new Store(':memory:'),calls:any[]=[],provider=fakeProvider(store,packetFor,calls),low={...intent,budgetMinor:21000,budgetScope:'party' as const,lockedFields:['budgetMinor']};
 const result=await provider.alternatives(low);assert.equal(result.length,2);assert.deepEqual(new Set(result.map(a=>a.intent.outboundDate)),new Set(['2026-10-23','2026-10-25']));
 for(const a of result){assert.deepEqual(a.changes.map(c=>c.field),['outboundDate']);assert.equal(a.changes[0]!.from,'2026-10-24');assert.equal(a.changes[0]!.to,a.intent.outboundDate);assert.equal(a.intent.budgetMinor,21000);assert.equal(a.intent.revision,2);assert.equal(violations(a.offer,a.intent).length,0);assert.equal(provider.cached(a.offer.id,a.intent).id,a.offer.id);assert.equal(new URL(a.offer.bookingURL!).searchParams.get('departureDate'),a.intent.outboundDate);}
 calls.length=0;assert.deepEqual(await provider.alternatives({...low,lockedFields:['budgetMinor','outboundDate']}),[]);assert.equal(calls.filter(c=>c.method==='tools/call').length,1);store.close();
});
test('live window alternatives respect date-window locks, fixed return and incoming connection constraints',async()=>{
 const store=new Store(':memory:'),calls:any[]=[],provider=fakeProvider(store,packetFor,calls),window={...intent,outboundDate:null,dateWindow:{start:'2026-10-24',end:'2026-10-24'},budgetMinor:21000,budgetScope:'party' as const,lockedFields:['budgetMinor'],tripType:'round_trip' as const,returnDate:'2026-10-30'};
 // Round-trip total is provider-reported 300 EUR, so use a 310 EUR fixed budget.
 const nearby=await provider.alternatives({...window,budgetMinor:31000});assert.equal(nearby.length,2);for(const a of nearby){assert.deepEqual(a.changes.map(c=>c.field),['dateWindow']);assert.equal(a.intent.returnDate,'2026-10-30');assert.equal(violations(a.offer,a.intent).length,0);}
 calls.length=0;assert.deepEqual(await provider.alternatives({...window,budgetMinor:31000,lockedFields:['budgetMinor','dateWindow']}),[]);assert.equal(calls.filter(c=>c.method==='tools/call').length,1);
 const incoming={airline:'Fictional airline',flightNumber:null,arrivalAirport:'SAW',arrivalAt:'2026-10-24T20:00:00Z',departureAirport:null,minimumConnectionMinutes:120,baggageReclaim:true,confirmed:true};
 const after=await provider.alternatives({...intent,budgetMinor:21000,budgetScope:'party',lockedFields:['budgetMinor'],incomingFlight:incoming});assert.equal(after.length,1);assert.equal(after[0]!.intent.outboundDate,'2026-10-25');assert.equal(after[0]!.intent.incomingFlight?.arrivalAt,incoming.arrivalAt);store.close();
});
