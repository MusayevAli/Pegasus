// Synthetic aggregate-only diagnostics: records offending field/token, never payloads or secrets.
import 'dotenv/config';
import OpenAI from 'openai';
import {writeFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {makeAnalyticsInsights} from '../src/analytics-insights.js';
const real=new OpenAI({apiKey:process.env.OPENAI_API_KEY,timeout:20000,maxRetries:0});
const providerStatuses:unknown[]=[];
const matches:Array<{requestId:string;field:string;token:string}>=[];
const forbidden=/(?:\d|%|\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|hundred|thousand|million|billion|percent|percentage|twice|double|half)\b)/ig;
const wrapped={responses:{parse:async(...args:Parameters<typeof real.responses.parse>)=>{
 const result=await real.responses.parse(...args);
 providerStatuses.push({id:result.id,status:result.status,incompleteDetails:result.incomplete_details,error:result.error,hasParsed:Boolean(result.output_parsed),refusals:result.output.flatMap((item:any)=>item.type==='message'?item.content.filter((c:any)=>c.type==='refusal').map((c:any)=>c.refusal):[])});
 for(const insight of (result.output_parsed as any)?.insights??[])for(const field of ['observation','hypothesis','proposedChange','suggestedExperiment'])for(const match of String(insight[field]).matchAll(forbidden))matches.push({requestId:result.id,field,token:match[0]});
 return result;
}}} as unknown as OpenAI;
const store=new Store('./data/tripfit.sqlite');
const result=await makeAnalyticsInsights(store,'synthetic',30,{client:wrapped});
if(result.source==='openai')writeFileSync('evidence/live-insight-results.json',JSON.stringify(result,null,2));
const diagnostics={source:result.source,diagnostics:result.diagnostics,matches,providerStatuses};
writeFileSync('evidence/live-insight-prose-diagnostics.json',JSON.stringify(diagnostics,null,2));
console.log(JSON.stringify(diagnostics,null,2));store.close();
