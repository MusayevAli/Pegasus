// Public read-only protocol discovery. Does not invoke PNR/account tools or print session headers.
import {writeFileSync} from 'node:fs';
const endpoint='https://mcp.flypgs.com/mcp';
let sessionId;
async function rpc(id,method,params){
 const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',Accept:'application/json, text/event-stream',...(sessionId?{'Mcp-Session-Id':sessionId}:{})},body:JSON.stringify({jsonrpc:'2.0',id,method,params}),signal:AbortSignal.timeout(15000)});
 sessionId=response.headers.get('mcp-session-id')??sessionId;
 const body=await response.text();
 const packets=body.startsWith('data:')||body.includes('\ndata:')?body.split('\n').filter(l=>l.startsWith('data:')).map(l=>JSON.parse(l.slice(5))):[JSON.parse(body)];
 return {status:response.status,authenticate:response.headers.get('www-authenticate'),packet:packets.find(p=>p.id===id)??packets[0]};
}
const init=await rpc(1,'initialize',{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'TripFit-readonly-verification',version:'1.0'}});
const list=await rpc(2,'tools/list',{});
const tools=list.packet?.result?.tools??[];
const result={verifiedAt:new Date().toISOString(),initializeStatus:init.status,initializeError:init.packet?.error??null,toolsListStatus:list.status,authenticationHeader:list.authenticate,toolNames:tools.map(t=>t.name),flightSearch:tools.find(t=>t.name==='flight-search')??null};
writeFileSync('evidence/pegasus-mcp-discovery.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
