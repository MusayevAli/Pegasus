import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {Store} from './db.js';
import {eventSchema,type Event} from './events.js';
import {analytics} from './analytics.js';
const uuid=(s:string)=>{const h=createHash('sha256').update(s).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;};
export function seed(store:Store,now=new Date()){
 if(store.db.prepare("SELECT value FROM meta WHERE key='seed-v2'").get())return false;
 // Upgrade only this reproducible synthetic fixture. Recorded prototype events are preserved.
 if(store.db.prepare("SELECT value FROM meta WHERE key='seed-v1'").get()){
  store.db.prepare("DELETE FROM events WHERE provenance='synthetic'").run();
  store.db.prepare("DELETE FROM meta WHERE key='seed-v1'").run();
 }
 const day=new Date(now);day.setUTCHours(0,0,0,0);const base=day.getTime()-2*86400000;const events:Event[]=[];
 for(let i=0;i<12;i++){
  const flowId=uuid(`flow${i}`),sessionId=uuid(`session${i}`);let sequence=0;let timestamp=base+i*3600000;
  const add=(name:Event['name'],screen:Event['screen'],properties:Event['properties']={},componentId='screen')=>{sequence++;events.push(eventSchema.parse({id:uuid(`${i}-${sequence}`),sessionId,flowId,name,screen,componentId,sequence,clientTimestamp:new Date(timestamp).toISOString(),appVersion:'1.0',schemaVersion:1,provenance:'synthetic',properties}));timestamp+=1000;};
  const journeyId=i<3?'solo':i<9?'family':'unsupported';const extras=i<3?0:i<6?25200:i<9?5000:0;
  add('search_submitted','search',{journeyId,origin:i>=9?'LAX':'SAW',destination:i>=9?'NRT':i<3?'AYT':'BCN',partySize:i<3?1:3},'search.submit');
  const max=i<6?5:i<9?3:1;const screens=['search','itinerary','configuration','review','checkout','confirmation'] as const;
  for(let j=0;j<max;j++){const screen=screens[j]!;const visitId=`visit-${i}-${j}`;add('screen_viewed',screen,{visitId});add('screen_duration',screen,{visitId,foregroundMs:(j+1)*10000+i*1000,activeMs:(j+1)*7000+i*500});if(j===1)add('offer_selected',screen,{journeyId,extrasMinor:extras},'itinerary.select');}
  if(i<9){const recommendationType=i<3?'keep_allowance':i<6?'bundle':'baggage';const r={recommendationId:`rec-${i}`,recommendationType} as const;add('recommendation_generated','configuration',r,'guidance.card');add('recommendation_visible','configuration',r,'guidance.card');add('recommendation_expanded','configuration',r,'guidance.card');if(i<6){add('recommendation_accepted','configuration',r,'guidance.apply');add('recommendation_applied','configuration',r,'guidance.apply');}else add('recommendation_dismissed','configuration',r,'guidance.dismiss');}
  if(i>=6&&i<9){for(let v=0;v<2;v++){const visitId=`baggage-${i}-${v}`;add('screen_viewed','baggage',{visitId});add('screen_duration','baggage',{visitId,foregroundMs:45000,activeMs:22000});}add('validation_error','baggage',{code:'baggage_mismatch'},'baggage.allowance');add('back_navigation','configuration',{previousScreen:'baggage'},'navigation.back');}
  if(i>=9)add('no_results','search',{origin:'LAX',destination:'NRT',resultCount:0},'search.results');
  if(i<6){add('checkout_started','checkout',{totalMinor:i<3?4500:74700,extrasMinor:extras},'checkout.demo');add('demo_booking_completed','confirmation',{totalMinor:i<3?4500:74700,extrasMinor:extras},'confirmation.summary');add('screen_viewed','confirmation',{visitId:`confirmation-${i}`});add('screen_duration','confirmation',{visitId:`confirmation-${i}`,foregroundMs:60000+i*1000,activeMs:42000+i*500});add('recommendation_retained','confirmation',{recommendationId:`rec-${i}`,recommendationType:i<3?'keep_allowance':'bundle'},'confirmation.summary');}
 }
 store.ingest(events,now.toISOString());store.db.prepare("INSERT INTO meta VALUES('seed-v2',?)").run(now.toISOString());return true;
}
export const knownSeedTotals={startedFlows:12,completedBookings:6,demoBookings:6,realTickets:0,completionRate:.5,medianCompletionMs:162500,errors:3,extrasSelectedMinor:90600,realisedRevenueMinor:0,activeFlows:0,abandonedFlows:6};
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){const store=new Store(process.env.DB_PATH??'./data/tripfit.sqlite');seed(store);const actual=analytics(store,'synthetic').overview;console.log(JSON.stringify({label:'Synthetic demo data',knownSeedTotals,actual},null,2));store.close();}
