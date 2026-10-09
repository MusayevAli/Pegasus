import 'dotenv/config';
import {writeFileSync} from 'node:fs';
import {Store} from '../src/db.js';
import {makeAnalyticsInsights} from '../src/analytics-insights.js';
const store=new Store('./data/v2-verification.sqlite');
const result=await makeAnalyticsInsights(store,'synthetic',30);
writeFileSync('evidence/live-insight-results.json',JSON.stringify(result,null,2));
console.log(JSON.stringify({source:result.source,insightCount:result.structuredInsights.length,diagnostics:result.diagnostics},null,2));
store.close();
