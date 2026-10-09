import {DatabaseSync} from 'node:sqlite';
import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import type {Event,StoredEvent} from './events.js';
export class Store {
  db: DatabaseSync;
  constructor(path:string){if(path!==':memory:')mkdirSync(dirname(path),{recursive:true});this.db=new DatabaseSync(path);this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, flow_id TEXT NOT NULL, provenance TEXT NOT NULL, client_at TEXT NOT NULL, received_at TEXT NOT NULL, payload TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS events_filter ON events(provenance,client_at);
CREATE INDEX IF NOT EXISTS events_session ON events(session_id);
CREATE TABLE IF NOT EXISTS quotes(id TEXT PRIMARY KEY,expires_at TEXT NOT NULL,payload TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS payments(idempotency_key TEXT PRIMARY KEY,request_hash TEXT NOT NULL,payload TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);`);}
  ingest(events:Event[],now=new Date().toISOString()){let accepted=0;this.db.exec('BEGIN IMMEDIATE');try{const s=this.db.prepare('INSERT OR IGNORE INTO events VALUES(?,?,?,?,?,?,?)');for(const e of events){accepted+=Number(s.run(e.id,e.sessionId,e.flowId,e.provenance,e.clientTimestamp,now,JSON.stringify(e)).changes);}this.db.exec('COMMIT');}catch(error){this.db.exec('ROLLBACK');throw error;}return {accepted,duplicates:events.length-accepted};}
  events(provenance='all',since='1970-01-01'):StoredEvent[]{const rows=this.db.prepare('SELECT payload,received_at FROM events WHERE (? = \'all\' OR provenance = ?) AND client_at >= ? ORDER BY client_at, received_at').all(provenance,provenance,since) as {payload:string;received_at:string}[];return rows.map(r=>({...JSON.parse(r.payload),serverReceivedAt:r.received_at}));}
  close(){this.db.close();}
}
