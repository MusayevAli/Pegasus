import type {Store} from '../db.js';
import type {SearchIntent,SearchResponse,OfferServices,BookingSelection,Quote,CatalogResponse} from '../../../shared/booking-v2.js';
import {search,services,quote} from './engine.js';
import {catalog} from './inventory.js';
import {V2Error} from './schema.js';
export interface FlightProvider {
 readonly id:string; readonly source:'sample'|'live';
 catalog():CatalogResponse;
 search(intent:SearchIntent):SearchResponse;
 services(offerId:string,party:Pick<SearchIntent,'adults'|'childAges'>):OfferServices;
 quote(offerId:string,intent:SearchIntent,selection:BookingSelection|null,revision:number):Quote;
}
export class SampleProvider implements FlightProvider {
 readonly id='sample';readonly source='sample' as const;
 constructor(private store:Store){}
 catalog(){return catalog();} search(intent:SearchIntent){return search(intent);}
 services(offerId:string,party:Pick<SearchIntent,'adults'|'childAges'>){return services(offerId,party);}
 quote(offerId:string,intent:SearchIntent,selection:BookingSelection|null,revision:number){return quote(this.store,offerId,intent,selection,revision);}
}
/** Boundary only: no guessed public REST endpoints or unauthorised MCP calls. */
export class PegasusNDCProvider {
 readonly id='pegasus_ndc';readonly source='live' as const;
 readonly documentedServices=['AirShopping','OfferPrice','ServiceList','SeatAvailability','OrderCreate','OrderChange'];
 readonly requiredSetup=['Business onboarding','Test credentials','Allowed server IP','Current partner schema mappings','Live certification'];
 available=false;
 search(_intent:SearchIntent):never{throw new V2Error('provider_unavailable','Authorised Pegasus NDC access is not configured. Choose labelled sample inventory explicitly.',503);}
 services(_offerId:string):never{return this.search({} as SearchIntent);}
 quote(_offerId:string):never{return this.search({} as SearchIntent);}
 createOrder():never{return this.search({} as SearchIntent);}
}
