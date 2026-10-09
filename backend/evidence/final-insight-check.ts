// One bounded service invocation using synthetic aggregates only. Saves success OR failure honestly.
import 'dotenv/config';
import {writeFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {makeAnalyticsInsights} from '../src/analytics-insights.js';
const store=new Store('./data/tripfit.sqlite');
try{
 const result=await makeAnalyticsInsights(store,'synthetic',30);
 writeFileSync('evidence/live-insight-results.json',JSON.stringify(result,null,2));
 writeFileSync('evidence/final-insight-verification.json',JSON.stringify({verifiedAt:new Date().toISOString(),inputProvenance:'synthetic aggregate records only',source:result.source,diagnostics:result.diagnostics,structuredInsights:result.structuredInsights},null,2));
 console.log(JSON.stringify({source:result.source,diagnostics:result.diagnostics,structuredInsights:result.structuredInsights},null,2));
 if(result.source!=='openai')process.exitCode=2;
}finally{store.close();}
