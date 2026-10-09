import {randomUUID,createHash} from 'node:crypto';
import {z} from 'zod';
import type {Store} from './db.js';
import {calculateQuote,quoteRequestSchema,RuleError} from './pricing.js';
export const paymentRequest=z.object({quoteID:z.string().uuid(),idempotencyKey:z.string().min(12).max(128),mode:z.enum(['demo','apple_pay']),paymentToken:z.string().max(100000).optional(),simulateOutcome:z.enum(['success','cancelled','failed']).optional()}).strict();
export interface PaymentProvider {authorize(input:{quoteID:string;amountMinor:number;currency:string;token:string},key:string):Promise<{authorizationID:string;status:'authorized'}>;capture(authorizationID:string,key:string):Promise<{captureID:string;status:'captured'}>;voidAuthorization(authorizationID:string,key:string):Promise<void>;}
export interface AirlineProvider {issue(input:{quoteID:string;captureID:string},key:string):Promise<{status:'issued';providerReference:string;ticketIDs:string[]}>;}
// This adapter contract must be implemented by your processor gateway. It is not a named provider integration.
export class GatewayPaymentProvider implements PaymentProvider {
 constructor(private baseURL:string,private token:string){if(!baseURL.startsWith('https://'))throw new Error('Processor gateway requires HTTPS');}
 private async request(path:string,body:unknown,key:string){const r=await fetch(new URL(path,this.baseURL),{method:'POST',headers:{Authorization:`Bearer ${this.token}`,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});if(!r.ok)throw new Error('processor_request_failed');return r.json();}
 async authorize(input:{quoteID:string;amountMinor:number;currency:string;token:string},key:string){return z.object({authorizationID:z.string(),status:z.literal('authorized')}).parse(await this.request('/authorizations',input,key));}
 async capture(authorizationID:string,key:string){return z.object({captureID:z.string(),status:z.literal('captured')}).parse(await this.request('/captures',{authorizationID},key));}
 async voidAuthorization(authorizationID:string,key:string){await this.request('/voids',{authorizationID},key);}
}
export class GatewayAirlineProvider implements AirlineProvider {
 constructor(private baseURL:string,private token:string){if(!baseURL.startsWith('https://'))throw new Error('Airline gateway requires HTTPS');}
 async issue(input:{quoteID:string;captureID:string},key:string){const r=await fetch(new URL('/tickets',this.baseURL),{method:'POST',headers:{Authorization:`Bearer ${this.token}`,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(input),signal:AbortSignal.timeout(15000)});if(!r.ok)throw new Error('airline_issuance_failed');return z.object({status:z.literal('issued'),providerReference:z.string(),ticketIDs:z.array(z.string()).min(1)}).parse(await r.json());}
}
export function createQuote(store:Store,body:unknown,now=new Date()){const input=quoteRequestSchema.parse(body);const calculated=calculateQuote(input);const quote={id:randomUUID(),...calculated,expiresAt:new Date(now.getTime()+15*60_000).toISOString(),revision:input.revision??0,input};store.db.prepare('INSERT INTO quotes VALUES(?,?,?)').run(quote.id,quote.expiresAt,JSON.stringify(quote));const {input:_,...publicQuote}=quote;return publicQuote;}
export function pay(store:Store,body:unknown,now=new Date()){
 const input=paymentRequest.parse(body);const hash=createHash('sha256').update(JSON.stringify({quoteID:input.quoteID,mode:input.mode,simulateOutcome:input.simulateOutcome??'success'})).digest('hex');
 const prior=store.db.prepare('SELECT request_hash,payload FROM payments WHERE idempotency_key=?').get(input.idempotencyKey) as {request_hash:string;payload:string}|undefined;
 if(prior){if(prior.request_hash!==hash)throw new RuleError('idempotency_conflict','This key belongs to a different payment request.');return JSON.parse(prior.payload);}
 const row=store.db.prepare('SELECT payload FROM quotes WHERE id=?').get(input.quoteID) as {payload:string}|undefined;if(!row)throw new RuleError('unknown_quote','Create a server quote before payment.');const quote=JSON.parse(row.payload);
 if(Date.parse(quote.expiresAt)<=now.getTime())throw new RuleError('expired_quote','The quote expired. Review a fresh quote.');
 const recalculated=calculateQuote(quoteRequestSchema.parse(quote.input));if(recalculated.totalMinor!==quote.totalMinor)throw new RuleError('quote_changed','Pricing changed. Review a fresh quote.');
 // Demo inventory can never reach a real payment provider, even when credentials are present.
 if(input.mode==='apple_pay')throw new RuleError('live_provider_unavailable','Demo inventory cannot be charged. Live inventory, processor and airline issuance adapters must be configured and verified together.');
 const alreadyCompleted=store.db.prepare("SELECT payload FROM payments WHERE json_extract(payload,'$.quoteID')=? AND json_extract(payload,'$.state')='completed_demo' LIMIT 1").get(input.quoteID) as {payload:string}|undefined;if(alreadyCompleted){store.db.prepare('INSERT INTO payments VALUES(?,?,?)').run(input.idempotencyKey,hash,alreadyCompleted.payload);return JSON.parse(alreadyCompleted.payload);}
 const outcome=input.simulateOutcome??'success';const result={quoteID:quote.id,state:outcome==='cancelled'?'cancelled':outcome==='failed'?'failed':'completed_demo',authorization:outcome==='success'?'simulated':'not_authorized',capture:'not_charged',issuance:'not_issued',reference:outcome==='success'?`DEMO-${randomUUID().slice(0,8).toUpperCase()}`:null,currency:quote.currency,totalMinor:quote.totalMinor,notice:'Simulation only. No charge occurred and no real ticket was issued.'};
 store.db.prepare('INSERT INTO payments VALUES(?,?,?)').run(input.idempotencyKey,hash,JSON.stringify(result));return result;
}
