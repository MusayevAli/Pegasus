import type {AnalyticsResponse,MetricRecord,SessionResponse} from '../../shared/analytics.js';
import type {StoredEvent} from './events.js';
import type {Store} from './db.js';
const STEPS=['search','itinerary','configuration','review','checkout','confirmation'];
const LABELS=['Search','Flight selected','Configuration','Review','Payment','Confirmation'];
const REC_TYPES=['baggage','meals','seating','bundle','connection','keep_allowance','alternative','flight_comparison'];
export const percentile=(values:number[],p:number):number=>{if(!values.length)return 0;const s=[...values].sort((a,b)=>a-b);const n=(s.length-1)*p;return Math.round((s[Math.floor(n)]??0)*(1-(n%1))+(s[Math.ceil(n)]??0)*(n%1));};
const number=(e:StoredEvent,key:string)=>typeof e.properties[key as keyof typeof e.properties]==='number'?e.properties[key as keyof typeof e.properties] as number:0;
const group=<T>(items:T[],key:(v:T)=>string)=>{const m=new Map<string,T[]>();for(const i of items){const k=key(i);const existing=m.get(k);if(existing)existing.push(i);else m.set(k,[i]);}return m;};
const flowKey=(e:StoredEvent)=>`${e.provenance}:${e.flowId}`;
const complete=(e:StoredEvent)=>e.name==='demo_booking_completed'||e.name==='ticket_issued';
const positiveConfig=(name:string,fallback:number)=>{const parsed=Number(process.env[name]);return Number.isFinite(parsed)&&parsed>0?parsed:fallback;};
function stage(e:StoredEvent){
 if(complete(e))return 5;
 if(e.name==='checkout_started'||e.name==='payment_outcome')return 4;
 if(e.name==='offer_selected')return 1;
 if(e.screen==='itinerary'||e.screen==='comparison'||e.screen==='import')return 0;
 return STEPS.indexOf(['baggage','seats','meals'].includes(e.screen)?'configuration':e.screen);
}
/** Passive telemetry must not keep an idle journey alive. */
function activityAt(e:StoredEvent):number|null {
 if(e.name==='screen_duration')return number(e,'activeMs')>0?Date.parse(e.clientTimestamp)-number(e,'foregroundMs')+number(e,'activeMs'):null;
 if(['loading_duration','recommendation_generated','recommendation_retained','ai_request_finished','quote_updated'].includes(e.name))return null;
 return Date.parse(e.clientTimestamp);
}
export function analytics(store:Store,provenance='synthetic',days=30,now=new Date()):AnalyticsResponse{
 const abandonmentMinutes=positiveConfig('ABANDONMENT_MINUTES',30);
 const min=Math.max(1,Math.floor(positiveConfig('ANALYTICS_MIN_SAMPLE',3)));
 const windowStart=new Date(now.getTime()-days*86400000).toISOString(),windowEnd=now.toISOString();
 const events=store.events(provenance,windowStart).filter(e=>Date.parse(e.clientTimestamp)<=now.getTime());
 const grouped=group(events,flowKey);for(const es of grouped.values())es.sort((a,b)=>Date.parse(a.clientTimestamp)-Date.parse(b.clientTimestamp)||a.sequence-b.sequence);
 const flows=[...grouped].filter(([,es])=>es.some(e=>e.name==='search_submitted')).map(([key,es])=>{
   const done=es.some(complete),last=es.at(-1)!;
   const activity=es.map(activityAt).filter((t):t is number=>t!==null).sort((a,b)=>a-b);
   const lastActive=activity.at(-1)??Date.parse(es[0]!.clientTimestamp);
   const resumed=es.some(e=>e.name==='journey_resumed')||activity.some((t,i)=>i>0&&t-activity[i-1]!>=abandonmentMinutes*60000);
   return {key,id:es[0]!.flowId,es,done,last,lastActive,resumed,stage:Math.max(...es.map(stage)),active:!done&&now.getTime()-lastActive<abandonmentMinutes*60000};
 });
 const validKeys=new Set(flows.map(f=>f.key));
 const cohortEvents=events.filter(e=>validKeys.has(flowKey(e))).sort((a,b)=>Date.parse(a.clientTimestamp)-Date.parse(b.clientTimestamp)||a.sequence-b.sequence);
 const durationGroups=group(cohortEvents.filter(e=>e.name==='screen_duration'),e=>`${flowKey(e)}:${e.properties.visitId}`);
 const loadingGroups=group(cohortEvents.filter(e=>e.name==='loading_duration'),e=>`${flowKey(e)}:${e.properties.visitId}`);
 const visitGroups=group(cohortEvents.filter(e=>e.name==='screen_viewed'),e=>`${flowKey(e)}:${e.properties.visitId??e.id}`);
 // Out-of-order upload of an entry must not drop a valid duration checkpoint.
 const visitKeys=new Set([...visitGroups.keys(),...durationGroups.keys(),...loadingGroups.keys()]);
 const time=[...visitKeys].map(id=>{
   const first=(visitGroups.get(id)??durationGroups.get(id)??loadingGroups.get(id))![0]!;
   return {id,key:flowKey(first),screen:first.screen,foreground:(durationGroups.get(id)??[]).reduce((s,e)=>s+number(e,'foregroundMs'),0),active:(durationGroups.get(id)??[]).reduce((s,e)=>s+number(e,'activeMs'),0),loading:(loadingGroups.get(id)??[]).reduce((s,e)=>s+number(e,'loadingMs'),0)};
 });
 const doneIDs=new Set(flows.filter(f=>f.done).map(f=>f.key));
 const completionTimes=(field:string)=>flows.filter(f=>f.done).map(f=>{
   const completionIndex=f.es.findIndex(complete);
   return f.es.slice(0,completionIndex+1).filter(e=>e.name==='screen_duration').reduce((s,e)=>s+number(e,field),0);
 }).filter(n=>n>0);
 const foregroundTimes=completionTimes('foregroundMs'),activeTimes=completionTimes('activeMs');
 // ID + version + journey + source is a distinct recommendation pair. Re-renders never multiply impressions.
 const recs=group(cohortEvents.filter(e=>e.name.startsWith('recommendation_')&&e.properties.recommendationId),e=>`${flowKey(e)}:${e.properties.recommendationId}:${e.properties.recommendationVersion??1}`);
 const recommendations=REC_TYPES.map(type=>{
   const rs=[...recs.values()].filter(es=>es[0]?.properties.recommendationType===type);
   const has=(es:StoredEvent[],name:string)=>es.some(e=>e.name===`recommendation_${name}`);
   const count=(name:string)=>rs.filter(es=>has(es,name)).length;
   const visible=rs.filter(es=>has(es,'visible'));
   const impressions=visible.length,accepts=visible.filter(es=>has(es,'accepted')).length;
   const retained=(es:StoredEvent[])=>has(es,'applied')&&has(es,'retained')&&es.filter(e=>['recommendation_applied','recommendation_reversed'].includes(e.name)).at(-1)?.name==='recommendation_applied';
   return {type,journeys:new Set(visible.map(es=>flowKey(es[0]!))).size,generated:count('generated'),impressions,expanded:visible.filter(es=>has(es,'expanded')).length,accepts,dismissals:visible.filter(es=>has(es,'dismissed')).length,applications:visible.filter(es=>has(es,'applied')).length,reversals:visible.filter(es=>has(es,'applied')&&has(es,'reversed')).length,retained:visible.filter(es=>doneIDs.has(flowKey(es[0]!))&&retained(es)).length,retainedAtCheckout:visible.filter(es=>retained(es)&&flows.find(f=>f.key===flowKey(es[0]!))!.stage>=4).length,acceptanceRate:impressions?accepts/impressions:0,pairDefinition:'Distinct recommendation ID/version × journey; accepts require an actually visible pair'};
 });
 const gapLabels:Record<string,string>={no_results:'Searches with no results',family_seating_unavailable:'Adjacent family seats unavailable',baggage_mismatch:'Baggage allowance conflict',unsupported_extra:'Unsupported extra',connection_too_short:'Connection rejected: too short'};
 const gaps=Object.entries(gapLabels).map(([code,label])=>{const es=cohortEvents.filter(e=>code==='no_results'?e.name==='no_results':e.name==='validation_error'&&e.properties.code===code);const r=es.find(e=>e.properties.origin&&e.properties.destination);return {code,label,count:es.length,flowCount:new Set(es.map(flowKey)).size,exampleRoute:r?`${r.properties.origin} → ${r.properties.destination}`:null};});
 const friction=[...group(time,t=>t.screen)].map(([screen,ts])=>{
   const completed=ts.filter(t=>doneIDs.has(t.key)),incomplete=ts.filter(t=>!doneIDs.has(t.key));
   return {screen,visits:ts.length,journeys:new Set(ts.map(t=>t.key)).size,revisits:ts.length-new Set(ts.map(t=>t.key)).size,foregroundMedianMs:percentile(ts.map(t=>t.foreground),.5),foregroundP90Ms:percentile(ts.map(t=>t.foreground),.9),activeMedianMs:percentile(ts.map(t=>t.active),.5),activeP90Ms:percentile(ts.map(t=>t.active),.9),loadingMedianMs:percentile(ts.map(t=>t.loading),.5),loadingTotalMs:ts.reduce((sum,t)=>sum+t.loading,0),backtracks:cohortEvents.filter(e=>e.name==='back_navigation'&&(e.properties.previousScreen??e.screen)===screen).length,errors:cohortEvents.filter(e=>(e.name==='validation_error'||e.name==='checkout_failed'||e.name==='payment_outcome'&&e.properties.paymentStatus==='failed')&&e.screen===screen).length,exits:flows.filter(f=>!f.done&&!f.active&&f.last.screen===screen).length,completedMedianMs:new Set(completed.map(t=>t.key)).size>=min?percentile(completed.map(t=>t.active),.5):null,incompleteMedianMs:new Set(incomplete.map(t=>t.key)).size>=min?percentile(incomplete.map(t=>t.active),.5):null};
 }).sort((a,b)=>b.activeMedianMs-a.activeMedianMs);
 const components=[...group(cohortEvents.filter(e=>!['screen_duration','loading_duration','screen_viewed','recommendation_generated','recommendation_visible','recommendation_retained','ai_request_finished'].includes(e.name)),e=>`${e.screen}:${e.componentId}`)].map(([,es])=>({screen:es[0]!.screen,componentId:es[0]!.componentId,interactions:es.length,errors:es.filter(e=>e.name==='validation_error').length})).sort((a,b)=>b.interactions-a.interactions).slice(0,30);
 const insights:AnalyticsResponse['insights']=[];
 const baggage=friction.find(f=>f.screen==='baggage');
 if(baggage&&new Set(cohortEvents.filter(e=>e.name==='back_navigation'&&(e.properties.previousScreen??e.screen)==='baggage').map(flowKey)).size>=min)insights.push({id:'baggage-clarity',title:'Make baggage inclusions easier to compare',issue:'Travellers return from baggage to compare their choices.',metric:`${baggage.backtracks} back actions from baggage across ${baggage.visits} visits`,sampleSize:baggage.journeys,cohort:'Baggage step',hypothesis:'Travellers may be unsure which allowance is already included. Backtracking alone does not establish confusion.',proposal:'Place a passenger-by-segment baggage inclusion summary on each fare card.',experiment:'Randomly compare current cards with the inclusion summary.',successMetric:'Lower baggage-to-fare backtracking, with no increase in review errors.',evidence:[{metricKey:'friction.baggage.backtracks',label:'Baggage back actions',value:baggage.backtracks},{metricKey:'friction.baggage.visits',label:'Baggage visits',value:baggage.visits}],source:'rules'});
 const gap=gaps.find(g=>g.code==='no_results');if(gap&&gap.flowCount>=min)insights.push({id:'search-recovery',title:'Help travellers recover from unsupported searches',issue:'Several searches return no available journeys.',metric:`${gap.flowCount} journeys with no results`,sampleSize:gap.flowCount,cohort:'Search',hypothesis:'The selected inventory may not match these requests; sample inventory is not evidence of real airline demand.',proposal:'Show supported airports and editable, verified alternatives in the empty state.',experiment:'Compare actionable alternatives with the existing empty state.',successMetric:'Share of no-result journeys that choose a supported search.',evidence:[{metricKey:'gaps.no_results.flowCount',label:'No-result journeys',value:gap.flowCount},{metricKey:'overview.startedFlows',label:'Started journeys',value:flows.length}],source:'rules'});
 const keep=recommendations.find(r=>r.type==='keep_allowance');if(keep&&keep.journeys>=min)insights.push({id:'keep-allowance',title:'Continue showing when no extra is needed',issue:'Keeping the existing allowance is a measurable recommendation outcome.',metric:`${keep.retained} retained no-extra recommendations from ${keep.impressions} visible pairs`,sampleSize:keep.journeys,cohort:'Visible keep-allowance journeys',hypothesis:'Clear allowance guidance may build confidence without increasing spend.',proposal:'Retain the no-extra recommendation and clarify its dimensions.',experiment:'Compare allowance explanation styles; do not optimise solely for extras value.',successMetric:'Fewer baggage corrections at review and stable completion.',evidence:[{metricKey:'recommendations.keep_allowance.impressions',label:'Visible recommendation pairs',value:keep.impressions},{metricKey:'recommendations.keep_allowance.retained',label:'Retained at confirmation',value:keep.retained}],source:'rules'});
 const completions=flows.filter(f=>f.done).length;
 const overview:AnalyticsResponse['overview']={startedFlows:flows.length,completedBookings:completions,demoBookings:flows.filter(f=>f.es.some(e=>e.name==='demo_booking_completed')).length,realTickets:flows.filter(f=>f.es.some(e=>e.name==='ticket_issued')).length,completionRate:flows.length?completions/flows.length:0,medianCompletionMs:foregroundTimes.length?percentile(foregroundTimes,.5):null,medianActiveCompletionMs:activeTimes.length?percentile(activeTimes,.5):null,p90ActiveCompletionMs:activeTimes.length?percentile(activeTimes,.9):null,errors:cohortEvents.filter(e=>e.name==='validation_error'||e.name==='checkout_failed'||e.name==='payment_outcome'&&e.properties.paymentStatus==='failed').length,extrasSelectedMinor:flows.reduce((s,f)=>s+number(f.es.filter(e=>e.properties.extrasMinor!==undefined).at(-1)??f.last,'extrasMinor'),0),realisedRevenueMinor:flows.reduce((s,f)=>s+number(f.es.find(e=>e.name==='ticket_issued')??{properties:{}} as StoredEvent,'totalMinor'),0),activeFlows:flows.filter(f=>f.active).length,abandonedFlows:flows.filter(f=>!f.active&&!f.done).length,resumedFlows:flows.filter(f=>f.resumed).length,currency:'EUR'};
 const funnel=STEPS.map((step,i)=>{const reached=flows.filter(f=>f.stage>=i),left=reached.filter(f=>f.stage===i&&!f.done),denominator=i===0?flows.length:flows.filter(f=>f.stage>=i-1).length;return {step,label:LABELS[i]!,reached:reached.length,denominator,dropoffs:denominator-reached.length,active:left.filter(f=>f.active).length,abandoned:left.filter(f=>!f.active).length,completed:reached.filter(f=>f.done).length};});
 const metrics:MetricRecord[]=[];
 const addMetric=(id:string,label:string,value:number,unit:MetricRecord['unit'],sampleSize:number,denominator:number,cohort:string)=>metrics.push({id,label,value,unit,sampleSize,denominator,windowStart,windowEnd,dataSource:provenance,cohort});
 for(const [key,value] of Object.entries(overview))if(typeof value==='number')addMetric(`overview.${key}`,key,value,key.endsWith('Ms')?'ms':key.endsWith('Minor')?'minor':key.endsWith('Rate')?'ratio':'count',key==='medianCompletionMs'?foregroundTimes.length:key==='medianActiveCompletionMs'||key==='p90ActiveCompletionMs'?activeTimes.length:flows.length,key.endsWith('Ms')?completions:flows.length,key.endsWith('Ms')?'Completed journeys with timing':'Started journeys');
 for(const f of friction)for(const key of ['visits','revisits','activeMedianMs','activeP90Ms','loadingTotalMs','backtracks','errors','exits'] as const)addMetric(`friction.${f.screen}.${key}`,`${f.screen}: ${key}`,f[key],key.endsWith('Ms')?'ms':'count',f.journeys,f.visits,f.screen);
 for(const r of recommendations)for(const key of ['impressions','accepts','applications','reversals','retained','retainedAtCheckout','acceptanceRate'] as const)addMetric(`recommendations.${r.type}.${key}`,`${r.type}: ${key}`,r[key],key==='acceptanceRate'?'ratio':'count',r.journeys,r.impressions,`${r.type} visible recommendation/journey pairs`);
 for(const g of gaps)addMetric(`gaps.${g.code}.flowCount`,g.label,g.flowCount,'count',g.flowCount,flows.length,g.code);
 for(const f of funnel)addMetric(`funnel.${f.step}.reached`,f.label,f.reached,'count',f.denominator,f.denominator,'Ordered booking funnel');
 return {meta:{provenance,days,generatedAt:windowEnd,windowStart,windowEnd,label:provenance==='synthetic'?'Synthetic demo data':provenance==='demo'?'Recorded prototype interactions':provenance==='live'?'Live events':'All sources (mixed provenance)',eventCount:cohortEvents.length,minimumCohort:min,abandonmentMinutes,activeTimeThresholdSeconds:positiveConfig('ACTIVE_TIME_THRESHOLD_SECONDS',30),timingDefinition:`Monotonic incremental foreground and active checkpoints sum by visit. Active time pauses after inactivity and in background. Loading is separately measured and may overlap foreground time. Completion stops at the confirmation event. Timing breakdowns below ${min} distinct journeys are suppressed.`,abandonmentDefinition:`Inferred after ${abandonmentMinutes} minutes without active interaction; passive idle checkpoints do not keep a journey ongoing. A new meaningful event reopens the same journey.`,funnelDefinition:'Distinct journeys with a search in this observation window. Flight selection requires selection or a later booking stage, not merely viewing results. Later stages imply prerequisite stages; optional bag/seat/meal screens fold into configuration.'},overview,funnel,friction,components,recommendations,gaps,sessions:flows.filter(f=>f.last.provenance!=='live').map(f=>({id:f.es[0]!.sessionId,flowId:f.id,provenance:f.last.provenance,startedAt:f.es.find(e=>e.name==='search_submitted')!.clientTimestamp,lastSeenAt:new Date(f.lastActive).toISOString(),status:f.done?'completed' as const:f.active?'active' as const:'abandoned' as const,resumed:f.resumed,durationMs:time.filter(t=>t.key===f.key).reduce((s,t)=>s+t.foreground,0),activeMs:time.filter(t=>t.key===f.key).reduce((s,t)=>s+t.active,0),loadingMs:time.filter(t=>t.key===f.key).reduce((s,t)=>s+t.loading,0),eventCount:f.es.length,errorCount:f.es.filter(e=>e.name==='validation_error'||e.name==='checkout_failed').length,lastScreen:f.last.screen})).sort((a,b)=>b.lastSeenAt.localeCompare(a.lastSeenAt)).slice(0,100),metrics,insights};
}
export function session(store:Store,id:string):SessionResponse|null{
 const events=store.events().filter(e=>e.sessionId===id&&e.provenance!=='live').sort((a,b)=>Date.parse(a.clientTimestamp)-Date.parse(b.clientTimestamp)||a.sequence-b.sequence);
 if(!events.length)return null;
 return {id,label:events[0]!.provenance==='synthetic'?'Synthetic demo session':'Consented prototype session',events:events.map(({id,name,sequence,flowId,screen,componentId,clientTimestamp,serverReceivedAt,properties})=>({id,name,sequence,flowId,screen,componentId,clientTimestamp,serverReceivedAt,properties}))};
}
