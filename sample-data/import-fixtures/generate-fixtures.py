from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import hashlib, json
root=Path(__file__).parent
font='/System/Library/Fonts/Supplemental/Arial.ttf'
cases={
'event-barcelona-verified.png':['FICTIONAL TEST DOCUMENT','Design Assembly','Conference','24 October 2026','15:00 Europe/Madrid','Fira Barcelona','Barcelona, Spain'],
'event-berlin-verified.png':['FICTIONAL TEST DOCUMENT','Night of Music','Concert','29 October 2026','20:30 Europe/Berlin','Arena Berlin','Berlin, Germany'],
'incoming-flight-verified.png':['FICTIONAL TEST DOCUMENT','Incoming flight itinerary','British Airways BA-DEMO-101','JFK to LGW','Arrival: 24 October 2026','08:00 Europe/London','Separately booked flight','Collect and re-check baggage']}
evidence=[]
for name,lines in cases.items():
    im=Image.new('RGB',(1000,1350),'white'); d=ImageDraw.Draw(im)
    d.rectangle((0,0,1000,145),fill='#ffcf00')
    for i,line in enumerate(lines): d.text((60,60+i*120),line,font=ImageFont.truetype(font,32 if i==0 else 44),fill='#191919')
    path=root/name; im.save(path)
    evidence.append({'file':name,'contents':lines,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'provenance':'Locally generated fictional QA text only, no user document or personal data'})
(root/'verified-fixture-manifest.json').write_text(json.dumps(evidence,indent=2))
print('Created three synthetic test images and exact-text SHA256 manifest.')
