import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type OpenAI from 'openai';
import {AIService,type GuidanceRequest} from '../src/ai.js';
import {parseLocalNeeds,validatePlan,type PlanOutput} from '../src/planning.js';
import {createApp} from '../src/server.js';
import {Store} from '../src/db.js';
const request:GuidanceRequest={revision:7,note:'We will bring gifts home and want vegetarian meals on each flight. Please sit together.',journeyId:'family',passengerTypes:['adult','adult','child'],segmentIds:['family-out','family-in'],preferences:[]};
const modelPlan:PlanOutput={revision:7,summary:'You want to sit together, enjoy vegetarian meals on both flights and leave room for gifts on your way home.',needs:{travellingLight:null,giftsOnReturn:true,stayTogether:true,noAlcohol:null,vegetarian:true,checkedBagEachWay:null,mealsEachFlight:true,packingItems:['gifts']},clarifications:[{id:'packing',question:'Will your gifts fit in your existing bag?',choices:['travel_light','checked_bag','skip']}]};
function provider(fn:(args:Record<string,unknown>)=>unknown|Promise<unknown>){return {responses:{parse:async(args:Record<string,unknown>)=>fn(args)}} as unknown as OpenAI;}

test('plan uses strict Responses API and preserves personalised model summary',async()=>{
 let sent:Record<string,unknown>|undefined;
 const ai=new AIService(provider(args=>{sent=args;return {output_parsed:modelPlan,status:'completed'};}));
 const result=await ai.plan(request);
 assert.equal(result.source,'openai');assert.equal(result.summary,modelPlan.summary);assert.equal(result.model,process.env.OPENAI_MODEL??'gpt-4.1-mini');assert.deepEqual(result.needs,modelPlan.needs);
 assert.deepEqual(Object.keys(result).sort(),['clarifications','model','needs','notice','revision','source','summary']);
 assert.equal(sent?.store,false);const text=sent?.text as {format:{type:string;name:string;strict:boolean;schema:Record<string,unknown>}};
 assert.equal(text.format.type,'json_schema');assert.equal(text.format.strict,true);assert.equal(text.format.name,'trip_needs_plan');
 assert.equal(text.format.schema.additionalProperties,false);
 assert.equal(JSON.stringify(sent).includes('paymentToken'),false);
});

test('plan local fallback preserves explicit negative needs and does not infer identity preferences',async()=>{
 const ai=new AIService(null);
 const negative=await ai.plan({...request,note:'We are not travelling light. We do not want gifts. Do not sit together. No alcohol. We are not vegetarian. No checked bags. No meals.'});
 assert.equal(negative.source,'local');assert.equal(negative.model,null);
 assert.deepEqual(negative.needs,{travellingLight:false,giftsOnReturn:false,stayTogether:false,noAlcohol:true,vegetarian:false,checkedBagEachWay:false,mealsEachFlight:false,packingItems:[]});
 assert.match(negative.notice,/not an AI interpretation/);
 const identity=await ai.plan({...request,note:'My name is Ali. We are visiting Spain with our child.'});
 assert.deepEqual(identity.needs,{travellingLight:null,giftsOnReturn:null,stayTogether:null,noAlcohol:null,vegetarian:null,checkedBagEachWay:null,mealsEachFlight:null,packingItems:[]});
});

test('local phrases distinguish rejected vegetarian meals from no meals, and unrelated negations',()=>{
 const vegetarian=parseLocalNeeds({...request,note:'We do not want vegetarian meals.'});assert.equal(vegetarian.vegetarian,false);assert.equal(vegetarian.mealsEachFlight,null);
 const mixed=parseLocalNeeds({...request,note:'No alcohol and gifts on return and vegetarian meals for everyone every flight.'});assert.equal(mixed.noAlcohol,true);assert.equal(mixed.giftsOnReturn,true);assert.equal(mixed.vegetarian,true);assert.equal(mixed.mealsEachFlight,true);
 const uncertain=parseLocalNeeds({...request,note:'Not sure about gifts. Maybe checked bags.'});assert.equal(uncertain.giftsOnReturn,null);assert.equal(uncertain.checkedBagEachWay,null);
 const bags=parseLocalNeeds({...request,note:'Checked bags for everyone each way. No meals. Just a laptop and clothes.'});assert.equal(bags.checkedBagEachWay,true);assert.equal(bags.mealsEachFlight,false);assert.deepEqual(bags.packingItems,['clothes','laptop']);
});

test('plan refuses unknown fields, missing nullable keys, stale revision and duplicate clarification IDs',async()=>{
 const invalid=[{...modelPlan,price:123}, {...modelPlan,needs:{travellingLight:true}}, {...modelPlan,revision:6}, {...modelPlan,clarifications:[modelPlan.clarifications[0],modelPlan.clarifications[0]]}];
 for(const value of invalid){const ai=new AIService(provider(()=>({output_parsed:value,status:'completed'})));const output=await ai.plan(request);assert.equal(output.source,'local');assert.match(output.notice,/could not return a valid plan/);}
 assert.throws(()=>validatePlan({...modelPlan,summary:'x'.repeat(401)},7));
});

test('refusal, incomplete output, timeout and rate limit return honest local plan',async()=>{
 const refused=new AIService(provider(()=>({output_parsed:null,status:'completed',output:[{type:'message',content:[{type:'refusal',refusal:'Cannot comply'}]}]})));
 assert.equal((await refused.plan(request)).source,'local');
 const incomplete=new AIService(provider(()=>({output_parsed:modelPlan,status:'incomplete'})));assert.equal((await incomplete.plan(request)).source,'local');
 for(const error of [new Error('timeout'),{status:429}]){const unavailable=new AIService(provider(()=>{throw error;}));assert.equal((await unavailable.plan(request)).source,'local');}
});

test('packing without credentials or an image never fabricates identified items',async()=>{
 const noKey=await new AIService(null).packing({revision:8,imageBase64:'aW1hZ2U=',mimeType:'image/jpeg'});
 assert.equal(noKey.source,'local');assert.equal(noKey.model,null);assert.deepEqual(noKey.candidates,[]);assert.deepEqual(noKey.items,[]);assert.deepEqual(noKey.questions,[]);assert.match(noKey.summary,/not been analysed/);
 let called=false;const noPhoto=await new AIService(provider(()=>{called=true;return {};})).packing({revision:8,imageBase64:null,mimeType:'image/jpeg'});assert.equal(called,false);assert.deepEqual(noPhoto.items,[]);assert.match(noPhoto.notice,/No photo was analysed/);
});

test('packing preserves visual model labels, confidence, summary and questions with compatible candidates',async()=>{
 let sent:Record<string,unknown>|undefined;
 const parsed={revision:8,summary:'I can see a folded shirt and what appears to be a laptop. Confirm these before choosing baggage.',items:[{category:'clothes',label:'Folded blue shirt',confidence:'high'},{category:'laptop',label:'Slim rectangular computer',confidence:'medium'}],questions:['Is the rectangular item a laptop?']};
 const ai=new AIService(provider(args=>{sent=args;return {output_parsed:parsed,status:'completed'};}));
 const result=await ai.packing({revision:8,imageBase64:'aW1hZ2U=',mimeType:'image/jpeg'});
 assert.equal(result.source,'openai');assert.equal(result.summary,parsed.summary);assert.deepEqual(result.items,parsed.items);assert.deepEqual(result.candidates,['clothes','laptop']);assert.equal(result.requiresConfirmation,true);assert.equal(sent?.store,false);
 assert.ok(JSON.stringify(sent).includes('data:image/jpeg;base64,aW1hZ2U='));
 const format=(sent?.text as {format:{strict:boolean}}).format;assert.equal(format.strict,true);
});

test('packing invalid categories, duplicate candidates, stale revision or refusal return no fake analysis',async()=>{
 const values=[{revision:7,summary:'A bag',items:[],questions:[]},{revision:8,summary:'A bag',items:[{category:'passport',label:'Document',confidence:'high'}],questions:[]},{revision:8,summary:'Clothes',items:[{category:'clothes',label:'Shirt',confidence:'high'},{category:'clothes',label:'Trousers',confidence:'high'}],questions:[]},null];
 for(const value of values){const ai=new AIService(provider(()=>({output_parsed:value,status:'completed'})));const r=await ai.packing({revision:8,imageBase64:'aW1hZ2U=',mimeType:'image/jpeg'});assert.equal(r.source,'local');assert.deepEqual(r.candidates,[]);assert.deepEqual(r.items,[]);}
});

test('AI status and plan routes require the app token and expose configuration without secrets',async()=>{
 const db=new Store(':memory:');const ai=new AIService(null);const server=createApp(db,{appToken:'device-token',ai}).listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();assert.ok(address&&typeof address!=='string');const url=`http://127.0.0.1:${address.port}`;
 try{
  assert.equal((await fetch(`${url}/api/ai/status`)).status,401);
  const status=await (await fetch(`${url}/api/ai/status`,{headers:{Authorization:'Bearer device-token'}})).json();assert.deepEqual(status,{configured:false,model:process.env.OPENAI_MODEL??'gpt-4.1-mini',features:['trip_plan','packing_vision','aggregate_insights']});
  const response=await fetch(`${url}/api/ai/plan`,{method:'POST',headers:{Authorization:'Bearer device-token','Content-Type':'application/json'},body:JSON.stringify(request)});assert.equal(response.status,200);const plan=await response.json() as {source:string};assert.equal(plan.source,'local');
 }finally{server.close();await once(server,'close');db.close();}
});


test('plan only extracts new note intent and clarifies missing whole-party flight scope',async()=>{
 const ai=new AIService(null);
 const light=await ai.plan({...request,note:'Travelling light, no checked bags, no meals.',preferences:['gifts','together','vegetarian']});
 assert.equal(light.needs.travellingLight,true);assert.equal(light.needs.giftsOnReturn,null);assert.equal(light.needs.stayTogether,null);assert.equal(light.needs.vegetarian,null);assert.equal(light.needs.checkedBagEachWay,false);assert.equal(light.needs.mealsEachFlight,false);
 const family=await ai.plan({...request,note:'We need checked bags and meals for everyone on each flight, seats together and space for gifts on the return. No alcohol.'});
 assert.equal(family.needs.checkedBagEachWay,true);assert.equal(family.needs.mealsEachFlight,true);assert.equal(family.needs.stayTogether,true);assert.equal(family.needs.giftsOnReturn,true);assert.equal(family.needs.noAlcohol,true);
 const uncertain=await ai.plan({...request,note:'I want a checked bag and meals.'});assert.equal(uncertain.needs.checkedBagEachWay,null);assert.equal(uncertain.needs.mealsEachFlight,null);assert.deepEqual(uncertain.clarifications.map(c=>c.id),['packing','meals']);
});
