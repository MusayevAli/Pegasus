// Adult-only synthetic sample data. No names, real itinerary, image or credential output.
import 'dotenv/config';
import OpenAI from 'openai';
import {readFileSync,writeFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {BookingAI} from '../src/v2/ai.js';
import {alternatives} from '../src/v2/routes.js';
import type {SearchIntent} from '../../shared/booking-v2.js';
const original=JSON.parse(readFileSync('evidence/live-search-results.json','utf8')).cases[2].intent as SearchIntent;
const intent={...original,budgetMinor:100,budgetScope:'party' as const,lockedFields:['originAirport','destinationAirports']};
const candidates=alternatives(intent),store=new Store('./data/v2-verification.sqlite');
const real=new OpenAI({apiKey:process.env.OPENAI_API_KEY,timeout:20000,maxRetries:0});
const diagnostics:unknown[]=[];
const wrapped={responses:{parse:async(...args:Parameters<typeof real.responses.parse>)=>{const r=await real.responses.parse(...args);diagnostics.push({requestId:r.id,status:r.status,incomplete:r.incomplete_details,cards:(r.output_parsed as any)?.cards});return r;}}} as unknown as OpenAI;
try{const response=await new BookingAI(store,wrapped).explainAlternatives(candidates,intent);const evidence={verifiedAt:new Date().toISOString(),source:'openai',model:response.model,requestId:response.requestId,explanations:response.explanations,candidateIds:candidates.map(c=>c.id),diagnostics};writeFileSync('evidence/live-alternatives-results.json',JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence,null,2));}catch(error){console.log(JSON.stringify({error:error instanceof Error?error.message:String(error),diagnostics},null,2));process.exitCode=1;}finally{store.close();}
