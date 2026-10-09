import {z} from 'zod';
import type {GuidanceRequest} from './ai.js';
export const packingCategory=z.enum(['clothes','laptop','gifts','sports','liquids']);
export const needsSchema=z.object({
  travellingLight:z.boolean().nullable(), giftsOnReturn:z.boolean().nullable(),
  stayTogether:z.boolean().nullable(), noAlcohol:z.boolean().nullable(),
  vegetarian:z.boolean().nullable(), checkedBagEachWay:z.boolean().nullable(),
  mealsEachFlight:z.boolean().nullable(), packingItems:z.array(packingCategory).max(5)
}).strict();
export const clarificationSchema=z.object({
  id:z.enum(['packing','meals','seating']),question:z.string().min(1).max(160),
  choices:z.array(z.enum(['travel_light','checked_bag','vegetarian','meals','no_meal','together','skip'])).min(2).max(7)
}).strict();
export const planOutput=z.object({revision:z.number().int().nonnegative(),summary:z.string().min(1).max(400),needs:needsSchema,clarifications:z.array(clarificationSchema).max(3)}).strict();
export type PlanNeeds=z.infer<typeof needsSchema>;
export type PlanOutput=z.infer<typeof planOutput>;
export type PlanResponse=PlanOutput & {source:'openai'|'local';model:string|null;notice:string};
const clean=(note:string)=>note.toLowerCase().replace(/[’‘]/g,"'").replace(/\bdon't\b/g,'do not').replace(/\bdoesn't\b/g,'does not').replace(/\bwon't\b/g,'will not').replace(/\bcan't\b/g,'cannot').replace(/\s+/g,' ').trim();
// Deliberately small English phrase parser. It never treats an unrecognised preference as false.
function explicit(text:string,positive:RegExp,negative:RegExp):boolean|null {
 if(negative.test(text))return false;
 return positive.test(text)?true:null;
}
export function parseLocalNeeds(input:GuidanceRequest):PlanNeeds {
 const raw=clean(input.note);const t=raw.replace(/\b(?:and|but|however)\b/g, ',');
 const n:PlanNeeds={travellingLight:null,giftsOnReturn:null,stayTogether:null,noAlcohol:null,vegetarian:null,checkedBagEachWay:null,mealsEachFlight:null,packingItems:[]};
 n.travellingLight=explicit(t,/\b(?:travel(?:ling|ing)?|pack(?:ing)?) light\b|\b(?:only|just) (?:a |one )?(?:small )?(?:backpack|underseat bag)\b|\bunderseat only\b/,/\b(?:not|never) (?:\w+ ){0,3}(?:travel(?:ling|ing)?|pack(?:ing)?) light\b|\bnot (?:a )?light (?:traveller|traveler|packer)\b/);
 n.giftsOnReturn=explicit(t,/\b(?:gifts?|souvenirs?)\b|\bshopping (?:on (?:the )?)?(?:return|way back)\b/,/\b(?:no|not|without|skip|avoid|avoiding) (?:\w+ ){0,4}(?:gifts?|souvenirs?|shopping)\b/);
 n.stayTogether=explicit(t,/\b(?:sit|sitting|seated|seats|stay|staying) (?:\w+ ){0,2}together\b|\badjacent seats\b|\bseats (?:next to|beside)\b/,/\b(?:no|not|without|avoid) (?:\w+ ){0,5}(?:together|adjacent seats)\b/);
 n.vegetarian=explicit(t,/\b(?:vegetarian|plant.based|meat.free)\b|\bno meat\b/,/\b(?:not|no|without|avoid) (?:\w+ ){0,3}(?:vegetarian|plant.based|meat.free)\b/);
 const rejectsAlcohol=/\b(?:no|not|never|without|avoid|avoiding|skip) (?:\w+ ){0,3}(?:alcohol|wine|beer)\b|\balcohol.free\b/.test(t);
 n.noAlcohol=rejectsAlcohol?true:/\b(?:want|include|drink|drinking|like) (?:\w+ ){0,2}(?:alcohol|wine|beer)\b/.test(t)?false:null;
 const noBags=/\b(?:no|not|without|skip|avoid) (?:\w+ ){0,4}checked (?:bags?|baggage|luggage)\b/.test(t);
 const bagMention=/\bchecked (?:bags?|baggage|luggage)\b/.test(t);
 const wholeParty=input.passengerTypes.length===1||/\b(?:everyone|everybody|all (?:of )?us|whole (?:family|party|group)|each (?:traveller|traveler|person|passenger)|every (?:traveller|traveler|person|passenger))\b/.test(raw);
 const directionalBags=/\bchecked (?:bags?|baggage|luggage)(?: \w+){0,3} (?:outbound|return) (?:only|leg only|flight only)\b|\b(?:outbound|return).only checked/.test(raw);
 const bothBags=/\bchecked (?:bags?|baggage|luggage)(?: \w+){0,5} (?:both|each|every) (?:way|ways|leg|legs|flight|flights|direction|directions)\b|\b(?:both|each|every) (?:way|leg|flight|direction)(?: \w+){0,5} checked (?:bag|baggage|luggage)\b/.test(raw);
 n.checkedBagEachWay=noBags?false:bagMention&&wholeParty&&!directionalBags&&(bothBags||input.segmentIds.length===1)?true:null;
 const noMeals=/\b(?:no|without|skip|avoid) (?:any |all |in.flight |onboard )?meals?\b|\b(?:do not|will not|not) (?:want|need|order|buy|have|eat|add) (?:any |all |in.flight |onboard )?meals?\b/.test(t);
 const mealsMention=/\bmeals?\b/.test(t);
 const eachMeal=/\bmeals?(?: \w+){0,4} (?:both|each|every) (?:flight|flights|leg|legs|way|ways)\b|\b(?:both|each|every) (?:flight|leg|way)(?: \w+){0,4} meals?\b/.test(raw);
 n.mealsEachFlight=noMeals?false:mealsMention&&wholeParty&&(eachMeal||input.segmentIds.length===1)?true:null;
 // Uncertainty is not a negative preference. Leave it for a confirmation chip.
 const uncertain=(topic:string)=>new RegExp(`\\b(?:not sure|unsure|maybe|perhaps|might|undecided)(?: \\w+){0,5} (?:${topic})\\b`).test(t);
 if(uncertain('gifts?|souvenirs?|shopping'))n.giftsOnReturn=null;
 if(uncertain('meals?|vegetarian')){n.mealsEachFlight=null;n.vegetarian=null;}
 if(uncertain('checked|bags?|baggage|packing')){n.checkedBagEachWay=null;n.travellingLight=null;}
 if(uncertain('together|seats|seating'))n.stayTogether=null;





 const categories:Array<[z.infer<typeof packingCategory>,RegExp,RegExp]>=[
  ['clothes',/\b(?:clothes|clothing|shirts?|trousers|dresses)\b/,/\b(?:no|not|without) (?:\w+ ){0,3}(?:clothes|clothing|shirts?|trousers|dresses)\b/],
  ['laptop',/\b(?:laptop|notebook computer)\b/,/\b(?:no|not|without) (?:\w+ ){0,3}(?:laptop|notebook computer)\b/],
  ['gifts',/\b(?:gifts?|souvenirs?)\b/,/\b(?:no|not|without) (?:\w+ ){0,4}(?:gifts?|souvenirs?)\b/],
  ['sports',/\b(?:sports equipment|golf clubs|skis|snowboard|bicycle|bike)\b/,/\b(?:no|not|without) (?:\w+ ){0,3}(?:sports equipment|golf clubs|skis|snowboard|bicycle|bike)\b/],
  ['liquids',/\b(?:liquids?|toiletries|shampoo|olive oil)\b/,/\b(?:no|not|without) (?:\w+ ){0,3}(?:liquids?|toiletries|shampoo|olive oil)\b/]
 ];
 for(const [category,yes,no] of categories)if(yes.test(t)&&!no.test(t))n.packingItems.push(category);

 return n;
}
export function fallbackPlan(input:GuidanceRequest,reason:'missing_credentials'|'unavailable'='missing_credentials'):PlanResponse {
 const needs=parseLocalNeeds(input);const details:string[]=[];
 if(needs.travellingLight===true)details.push('travel light');else if(needs.travellingLight===false)details.push('pack beyond a light bag');
 if(needs.giftsOnReturn===true)details.push('bring gifts home');else if(needs.giftsOnReturn===false)details.push('skip return gifts');
 if(needs.checkedBagEachWay===true)details.push('use checked baggage on each flight');else if(needs.checkedBagEachWay===false)details.push('avoid checked bags');
 if(needs.stayTogether===true)details.push('look for seats together');else if(needs.stayTogether===false)details.push('skip adjacent-seat guidance');
 if(needs.mealsEachFlight===false)details.push('skip meals');else if(needs.mealsEachFlight===true)details.push('consider meals on each flight');
 if(needs.vegetarian===true)details.push('prefer vegetarian food');else if(needs.vegetarian===false)details.push('not require vegetarian food');
 if(needs.noAlcohol===true)details.push('avoid alcohol');
 const clarifications:PlanOutput['clarifications']=[];
 const t=clean(input.note);
 if(needs.checkedBagEachWay===null&&needs.travellingLight===null&&/\b(?:bags?|baggage|packing|luggage|sports|ski|gifts?|souvenirs?)\b/.test(t))clarifications.push({id:'packing',question:'Should the comparison add checked baggage for every traveller on every flight?',choices:['travel_light','checked_bag','skip']});
 if(needs.mealsEachFlight===null&&/\b(?:meals?|food|vegetarian|hungry)\b/.test(t))clarifications.push({id:'meals',question:'Would every traveller like a meal on each supported flight?',choices:['meals','no_meal','skip']});
 if(needs.stayTogether===null&&/\b(?:seats?|seating|together)\b/.test(t))clarifications.push({id:'seating',question:'Should we look for seats together?',choices:['together','skip']});
 const summary=details.length?`From the phrases I could match: ${details.join('; ')}. Review these needs before comparing options.`:'I could not confidently match a booking preference. Choose a need below or keep your current selections.';
 return {revision:input.revision,source:'local',model:null,summary:summary.slice(0,400),needs,clarifications,notice:reason==='missing_credentials'?'AI is not connected. This is a limited local phrase match, not an AI interpretation. Your choices have not changed.':'AI could not return a valid plan. This limited local phrase match is a fallback. Your choices have not changed.'};
}
export function validatePlan(value:unknown,revision:number):PlanOutput {
 const parsed=planOutput.parse(value);if(parsed.revision!==revision)throw new Error('stale_revision');
 if(new Set(parsed.clarifications.map(c=>c.id)).size!==parsed.clarifications.length)throw new Error('duplicate_clarification');
 for(const c of parsed.clarifications)if(new Set(c.choices).size!==c.choices.length)throw new Error('duplicate_choice');
 parsed.needs.packingItems=[...new Set(parsed.needs.packingItems)];return parsed;
}
