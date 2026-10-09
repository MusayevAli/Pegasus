// Uses only adult-only synthetic QA search facts already recorded by live-search-check.
import {readFileSync,writeFileSync} from 'node:fs';
const source=JSON.parse(readFileSync('evidence/live-search-results.json','utf8'));
const intent=source.cases[2].intent;
async function post(path,body){const response=await fetch('http://127.0.0.1:3002/api/v2'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await response.json();if(!response.ok)throw new Error(JSON.stringify({status:response.status,result}));return result;}
const found=await post('/flights/search',{intent});
const comparison=await post('/ai/compare',{revision:intent.revision,intent,offerIds:found.offers.slice(0,2).map(o=>o.id)});
const constrained={...intent,revision:intent.revision+1,budgetMinor:100,budgetScope:'party',lockedFields:['originAirport','destinationAirports']};
const noMatch=await post('/flights/search',{intent:constrained});
const alternatives=await post('/search/alternatives',{intent:constrained});
const validated=[];
for(const alternative of alternatives.alternatives){const result=await post('/flights/search',{intent:alternative.intent});validated.push({id:alternative.id,offerId:alternative.offer.id,found:result.offers.some(o=>o.id===alternative.offer.id),changes:alternative.changes});}
if(noMatch.totalMatches!==0||validated.some(v=>!v.found))throw new Error('Candidate validation failed');
const evidence={verifiedAt:new Date().toISOString(),inputProvenance:'adult-only synthetic QA search facts',comparison,alternatives,noMatchCount:noMatch.totalMatches,validated};
writeFileSync('evidence/live-comparison-results.json',JSON.stringify(evidence,null,2));
console.log(JSON.stringify({comparisonSource:comparison.explanationSource,comparisonRequestId:comparison.requestId,comparisonExplanation:comparison.explanation,alternativesSource:alternatives.explanationSource,alternativesRequestId:alternatives.requestId,validated},null,2));
