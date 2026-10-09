// Public, inspected object photos and synthetic event screenshots only. Never logs image bytes or secrets.
import {readFileSync,writeFileSync} from 'node:fs';
const type=process.argv[2]??'packing';
const files=process.argv.slice(3);
const results=[];
for(const [index,path]of files.entries()){
 const bytes=readFileSync(path);const mimeType=path.toLowerCase().endsWith('.png')?'image/png':'image/jpeg';
 const body={revision:100+index,imageBase64:bytes.toString('base64'),mimeType,...(type==='trip-import'?{context:{currentDate:'2026-10-08',locale:'en-US',timeZone:'America/Los_Angeles'}}:{})};
 const r=await fetch(`http://127.0.0.1:3002/api/v2/ai/${type}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await r.json();
 results.push({inputName:path.split('/').at(-1),inputProvenance:type==='packing'?'public object photograph, inspected: no faces':'synthetic event document with no personal data',status:r.status,result});
}
writeFileSync(`evidence/live-${type}-results.json`,JSON.stringify({verifiedAt:new Date().toISOString(),results},null,2));console.log(JSON.stringify(results,null,2));
