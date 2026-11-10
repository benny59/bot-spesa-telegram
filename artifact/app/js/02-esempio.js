"use strict";
// ---------- Example: the 21 Oct 2026 ALDI SÜD receipt, transcribed ----------
const EXAMPLE = {store:"ALDI SÜD Frankfurt", date:"2026-10-21", total:103.31, items:[
 ["488786","Thunf. Oliv.Öl",3,"pc",1.79,"fish"],["625269","Kichererbsen 400g",1,"pc",0.59,"veg"],
 ["540697","Bio-Gemüsemais",1,"pc",0.99,"veg"],["415589","Bio-Joghurt 1kg",1,"pc",1.99,"dairy"],
 ["280132","Orangendirektsaft",1,"pc",2.00,"drinks"],["80000291","Pfand",1,"pc",0.25,EXCLUDED],
 ["536728","Bio-Kimchi",1,"pc",3.99,"veg"],["211635","Tragetasche Altp",2,"pc",0.25,EXCLUDED],
 ["493388","Bio PNL FriMil.3,8",1,"pc",1.45,"dairy"],["290288","Oatly Haferdrink",1,"pc",1.79,"dairy"],
 ["487869","Bio NL Kaesesch.",1,"pc",2.39,"dairy"],["308244","Innocent Smoothie",2,"pc",1.49,"drinks"],
 ["80000472","Pfand",2,"pc",0.25,EXCLUDED],["509949","Apfel Bio KD 1kg",1,"pc",2.29,"fruit"],
 ["700000","Bio PNL Lachsfilet",2,"pc",7.99,"fish"],["229113","Blumenkohl Stk",1,"pc",1.49,"veg"],
 ["304390","Bio Avocado 2 Stk",1,"pc",2.29,"fruit"],["229396","Bananen Bio",0.802,"kg",1.99,"fruit"],
 ["482464","Zitronen Bio 500g",1,"pc",1.49,"fruit"],["520576","Bio Knödel",2,"pc",3.29,"bread"],
 ["540971","Bio NL Käsestücke",1,"pc",2.29,"dairy"],["227872","Granatäpfel Stück",1,"pc",1.29,"fruit"],
 ["494015","Bio NL Basmati",1,"pc",2.25,"bread"],["699024","Bio Bliss Balls",3,"pc",0.99,"sweets"],
 ["230122","Gurke Bio Stk",1,"pc",1.19,"veg"],["228039","Bio-Zucchini 500g",1,"pc",1.49,"veg"],
 ["723768","NNN Das Pure",1,"pc",1.75,"bread"],["591777","Bio P Tempeh",1,"pc",2.99,"other"],
 ["230052","Auberginen Stk",1,"pc",0.79,"veg"],["541215","Bio Leinsamen/Chia",1,"pc",1.55,"other"],
 ["230729","Fenchel",0.334,"kg",2.49,"veg"],["271186","Walnusskerne",1,"pc",2.49,"fruit"],
 ["229338","Kiwi grün Stück",1,"pc",0.49,"fruit"],["230299","Brokkoli 400g",1,"pc",1.29,"veg"],
 ["715394","Ramen Udon Nudeln",1,"pc",1.29,"bread"],["202687","Körn. Frischkäse",1,"pc",1.19,"dairy"],
 ["508033","RoteBeet Bio vak 500g",1,"pc",1.49,"veg"],["512062","Bio-Hähnbr.filet",1,"pc",2.99,"meat"],
 ["202680","Bio-Mozzarel. 125g",2,"pc",1.29,"dairy"],["471594","Bio Mand/Waln Mix",1,"pc",2.55,"fruit"],
 ["706639","Bio-Babyspinat",1,"pc",1.29,"veg"],["579966","Bio Büffelmozz.",1,"pc",2.19,"dairy"],
 ["113425","Bergader Weichkäse",1,"pc",1.79,"dairy"],["645941","DatCherTo Bio 250g",1,"pc",2.89,"veg"],
 ["202291","Bio-Feta",1,"pc",2.89,"dairy"],
].map(([code,name,qty,unit,unitPrice,cat]) => ({code,name,qty,unit,unitPrice,price:round2(qty*unitPrice),cat}))};
EXAMPLE.items.find(i=>i.code==="229396").price = 1.60;
EXAMPLE.items.find(i=>i.code==="230729").price = 0.83;
