"use strict";
// ---------- Nutrition ----------
const NUT = [
  {k:"kcal", n:"Energy",        u:"kcal"},
  {k:"p",    n:"Protein",       u:"g", ref:25,  good:true},
  {k:"fib",  n:"Fibre",         u:"g", ref:15,  good:true},
  {k:"f",    n:"Fat",           u:"g", ref:35},
  {k:"sf",   n:"Saturated fat", u:"g", ref:10},
  {k:"c",    n:"Carbohydrate",  u:"g", ref:130},
  {k:"s",    n:"Sugars",        u:"g", ref:45},
  {k:"salt", n:"Salt",          u:"g", ref:3},
  {k:"n3",   n:"Omega-3 fats",  u:"g", ref:0.7, good:true, x:"fat2"},
  {k:"mufa", n:"Monounsaturated fat", u:"g", x:"fat2"},
  {k:"pufa", n:"Polyunsaturated fat", u:"g", x:"fat2"},
  {k:"grainK", n:"Energy from grain products", u:"kcal", calc: it => it.wg != null ? (Number(it.nut?.kcal)||0) : 0},
  {k:"wgK",    n:"Energy from wholegrain", u:"kcal", calc: it => it.wg != null ? (Number(it.nut?.kcal)||0)*Math.max(0,Math.min(100,Number(it.wg)||0))/100 : 0},
  {k:"co2",    n:"Climate footprint", u:"g CO₂e", co2:true},
];
let nutPeriod = "all", nutMetric = "npe";
// =====================================================================
// Climate: kg CO2e per kg of food as bought, at the shop shelf in Germany (farm, processing, packaging,
// transport and retail; not home cooking). ifeu 2020 for the Umweltbundesamt; "e" marks our own estimate
// for a product the study doesn't list, from its nearest neighbours.
// =====================================================================
const CO2T = {
  beef:[13.6,"Beef"], mince:[9.2,"Mince, mixed"], pork:[4.6,"Pork"], chicken:[5.5,"Poultry"], sausage:[2.9,"Sausage"], ham:[6.0,"Ham, cured meat",1],
  fishfarm:[5.1,"Fish, farmed (salmon)"], fishwild:[2.4,"Fish, wild"], fishfing:[2.0,"Fish fingers",1], tuna:[3.0,"Tinned fish",1], prawns:[12.5,"Prawns"],
  milk:[1.4,"Milk"], yogurt:[1.7,"Yogurt, kefir"], quark:[3.3,"Quark, skyr, cottage cheese"], cream:[4.2,"Cream"], butter:[9.0,"Butter"],
  cheese:[5.7,"Cheese"], hardcheese:[6.3,"Parmesan, Grana"], freshcheese:[5.5,"Fresh cheese, mozzarella"], feta:[7.0,"Feta"], eggs:[3.0,"Eggs"],
  plantdrink:[0.3,"Oat or soy drink"], dessert:[2.0,"Dairy desserts",1],
  tofu:[1.0,"Tofu"], tempeh:[0.7,"Tempeh"], meatsub:[1.8,"Meat substitutes"], lentils:[1.2,"Dried pulses"], pulsestin:[1.3,"Tinned pulses"],
  bread:[0.6,"Bread"], rolls:[0.7,"Rolls"], pastry:[1.6,"Cakes, pastries, biscuits"], pasta:[0.7,"Pasta, noodles"], rice:[3.1,"Rice"], oats:[0.6,"Oats"], muesli:[1.0,"Muesli, cereals",1], grain:[0.7,"Other grain products",1],
  potatoes:[0.2,"Potatoes"], roots:[0.15,"Carrots, roots"], brassica:[0.3,"Cabbages, broccoli"], leafy:[0.4,"Salad, spinach"], tomatoes:[0.8,"Tomatoes"], cucumber:[0.4,"Cucumber"],
  squash:[0.2,"Courgette, aubergine, pumpkin, fennel"], peppers:[0.6,"Peppers"], mushrooms:[1.3,"Mushrooms"], onions:[0.2,"Onions, leeks"], herbs:[1.5,"Fresh herbs",1],
  vegjar:[1.3,"Tinned or jarred veg, passata"], tomconc:[4.3,"Dried tomatoes, tomato paste"], vegfrozen:[0.7,"Frozen vegetables"],
  apples:[0.3,"Apples, pears"], citrus:[0.3,"Citrus"], bananas:[0.6,"Bananas"], grapes:[0.4,"Grapes"], berries:[1.2,"Berries",1], avocado:[0.6,"Avocado"],
  tropical:[0.9,"Mango, pineapple, kiwi"], fruit:[0.5,"Other fruit",1], dried:[1.0,"Dried fruit",1], freezedried:[5.0,"Freeze-dried fruit",1],
  nuts:[2.0,"Nuts",1], seeds:[1.0,"Seeds",1], nutbutter:[2.0,"Nut butter, tahini"], olive:[3.2,"Olive oil"], oil:[3.3,"Other oils"], margarine:[2.8,"Margarine"],
  chocolate:[4.1,"Chocolate"], sweets:[1.5,"Sweets, biscuits",1], sugar:[0.7,"Sugar"], honey:[2.0,"Honey"], jam:[1.0,"Jam, spreads",1], balls:[1.5,"Energy balls",1],
  oj:[0.7,"Orange juice"], juice:[0.4,"Apple and other juice"], smoothie:[0.8,"Smoothies",1], soft:[0.4,"Soft drinks"], water:[0.2,"Mineral water"],
  coffee:[5.6,"Coffee"], cocoa:[5.0,"Cocoa"], tea:[2.0,"Tea",1], spices:[2.0,"Spices",1], sauces:[1.5,"Sauces, condiments",1], other:[1.5,"Other food",1],
};
const CO2_GROUPS = [
  ["Meat", ["beef","mince","pork","chicken","sausage","ham"]], ["Fish", ["fishfarm","fishwild","fishfing","tuna","prawns"]],
  ["Cheese", ["cheese","hardcheese","freshcheese","feta"]], ["Milk, yogurt, cream, butter", ["milk","yogurt","quark","cream","butter","dessert"]], ["Eggs", ["eggs"]],
  ["Plant protein", ["tofu","tempeh","meatsub","lentils","pulsestin","plantdrink"]], ["Grains, bread, pasta, rice", ["bread","rolls","pastry","pasta","rice","oats","muesli","grain"]],
  ["Vegetables, potatoes", ["potatoes","roots","brassica","leafy","tomatoes","cucumber","squash","peppers","mushrooms","onions","herbs","vegjar","tomconc","vegfrozen"]],
  ["Fruit", ["apples","citrus","bananas","grapes","berries","avocado","tropical","fruit","dried","freezedried"]], ["Nuts, seeds, oils", ["nuts","seeds","nutbutter","olive","oil","margarine"]],
  ["Sweets, sugar", ["chocolate","sweets","sugar","honey","jam","balls"]], ["Drinks, coffee, tea", ["oj","juice","smoothie","soft","water","coffee","cocoa","tea"]], ["Other", ["spices","sauces","other"]],
];
const CO2_GROUP_OF = Object.fromEntries(CO2_GROUPS.flatMap(([n, ks]) => ks.map(k => [k, n])));
// Name rules (generic English name first, then the receipt text) for lines saved before climate types were read.
const CO2_RULES = [
  [/pingui|milchschnitte|milk slice/, "dessert"], [/chocolate|schoko|kinder|bueno|milka|ritter|lindt|nutella|cocoa spread/, "chocolate"],
  [/chili crunch|chilli oil|chili oil/, "sauces"], [/rice cake|rice waffle|reiswaf/, "grain"],
  [/freeze-dried|gefriergetr/, "freezedried"], [/fish finger|fischstäb/, "fishfing"], [/prawn|shrimp|garnel/, "prawns"],
  [/tuna|thunf|sardine|mackerel in|makrele/, "tuna"], [/salmon|lachs|trout|forelle|dorade|pangasius/, "fishfarm"], [/fish|fisch|cod|kabeljau|seelachs/, "fishwild"],
  [/mince|hackfl|\bhack\b/, "mince"], [/beef|rind|steak|veal|kalb/, "beef"], [/\bham\b|schinken|prosciutto|crudo|bresaola|salami|speck|bacon/, "ham"],
  [/sausage|wurst|würst|frankfurter|wiener|chorizo|mortadella/, "sausage"], [/chicken|hähn|haehn|huhn|turkey|pute|poultry|geflügel/, "chicken"], [/pork|schwein/, "pork"],
  [/oat drink|soy drink|haferdrink|sojadrink|almond drink|mandeldrink|plant drink/, "plantdrink"], [/tofu/, "tofu"], [/tempeh/, "tempeh"],
  [/vegan|veggie|valess|rügenwalder|meat substitute/, "meatsub"],
  [/tahini|peanut butter|erdnussbutter|nut butter|nussmus|mandelmus/, "nutbutter"],
  [/butter(?!milk|milch|keks)/, "butter"], [/margarin|\brama\b|becel|streichf/, "margarine"],
  [/parmesan|parmig|\bgrana\b|pecorino/, "hardcheese"], [/feta|halloumi/, "feta"], [/mozzarella|burrata|ricotta|cream cheese|frischkäse|mascarpone|cottage|körn/, "freshcheese"],
  [/quark|skyr/, "quark"], [/cheese|käse|kaese|gouda|emmentaler|babybel|camembert|brie/, "cheese"],
  [/ice cream|eiscreme|\beis\b/, "dessert"], [/cream|sahne|crème|creme fra|schmand/, "cream"], [/yogurt|yoghurt|joghurt|kefir|buttermilk|buttermilch|ayran/, "yogurt"], [/pudding|mousse|dessert|grießbrei|milchreis/, "dessert"],
  [/milk|milch|frimil/, "milk"], [/\begg|eier\b|\beier/, "eggs"],
  [/lentil|linsen|split pea|dried bean/, "lentils"], [/chickpea|kichererb|kidney|white bean|weiße bohnen|black bean|beans in|baked bean/, "pulsestin"],
  [/dried tomato|getr.* tomat|tomato paste|tomatenmark/, "tomconc"], [/passata|tomato sauce|tomatensauce|chopped tomat|gehackte tomat|pelati|sweetcorn|mais|olive(?!n?öl| oil)|artichoke|artischo|pickle|gurken im|kimchi|sauerkraut|roasted pepper|antipast/, "vegjar"],
  [/frozen veg|tk |tiefkühl|rahmspinat|erbsen/, "vegfrozen"],
  [/olive oil|olivenöl/, "olive"], [/\boil\b|öl\b|rapsöl|sonnenblumenöl/, "oil"],
  [/chia|linseed|leinsamen|sesame|sesam|pumpkin seed|kürbiskern|sunflower seed|sonnenblumenkern|hemp/, "seeds"],
  [/nut|nuss|nüss|almond|mandel|cashew|pistach|hazel|haselnuss|pecan|macadamia|pine kernel|pinien|maroni|chestnut/, "nuts"],
  [/bliss|energy ball|protein ball/, "balls"], [/honey|honig/, "honey"], [/jam|marmelade|konfitüre|fruit spread|aufstrich/, "jam"], [/\bsugar|zucker/, "sugar"],
  [/gummy|gumm|haribo|sweets|bonbon|lolli|candy/, "sweets"], [/biscuit|keks|cookie|cake|kuchen|croissant|brioche|waffle|waffel|muffin|pastry|gebäck|plätzchen/, "pastry"],
  [/rice|reis|risotto|basmati/, "rice"], [/oat|hafer|porridge/, "oats"], [/muesli|müsli|granola|cornflakes|cereal/, "muesli"],
  [/pasta|spaghetti|penne|fusilli|noodle|nudel|udon|ramen|lasagn|tortellini|gnocchi/, "pasta"], [/roll|brötchen|pretzel|brezel|laugen|baguette|ciabatta/, "rolls"],
  [/bread|brot|toast|crispbread|knäcke|pinsa|wrap|tortilla|pita/, "bread"], [/flour|mehl|couscous|bulgur|polenta|quinoa|semolina|grieß|knödel|dumpling/, "grain"],
  [/potato|kartoffel|sweet potato|süßkartoffel/, "potatoes"], [/carrot|karott|möhr|beetroot|rote be|parsnip|pastinak|celeriac|sellerie|radish|radies|kohlrabi|ginger|ingwer/, "roots"],
  [/broccoli|brokkoli|cauliflower|blumenkohl|cabbage|kohl|brussels|rosenkohl|kale|pak choi/, "brassica"],
  [/cucumber|gurke/, "cucumber"],
  [/spinach|spinat|lettuce|salad|salat|rocket|rucola|lamb's|feldsalat|chard|mangold/, "leafy"], [/herb|kräuter|basil|basilik|parsley|petersil|coriander|koriander|dill|chives|schnittlauch|mint|minze/, "herbs"],
  [/tomato|tomat/, "tomatoes"], [/courgette|zucchini|aubergine|pumpkin|kürbis|hokkaido|fennel|fenchel|squash/, "squash"],
  [/pepper|paprika(?! edels| pulver)|chili/, "peppers"], [/mushroom|champign|pilz/, "mushrooms"], [/onion|zwiebel|leek|lauch|garlic|knoblauch|shallot|schalotte/, "onions"],
  [/orange juice|orangen?saft|orangendirekt/, "oj"], [/apple juice|apfelsaft|juice|saft|nektar/, "juice"], [/smoothie|true fruits/, "smoothie"], [/water|wasser|sprudel/, "water"], [/cola|lemonade|limo|soft drink|eistee|ice tea/, "soft"],
  [/coffee|kaffee|espresso/, "coffee"], [/cocoa|kakao/, "cocoa"], [/\btea\b|tee\b/, "tea"],
  [/date|dattel|raisin|rosine|dried|getrockn|apricot dried|cranberr.*dried|prune|pflaume getr/, "dried"],
  [/pomegranate|granatap/, "tropical"], [/banana|banane/, "bananas"], [/apple|apfel|pear|birne/, "apples"], [/orange|lemon|zitron|lime|limette|mandarin|clementin|grapefruit/, "citrus"],
  [/grape|traube/, "grapes"], [/berr|beere|cherry|kirsch/, "berries"], [/avocado/, "avocado"], [/mango|pineapple|ananas|kiwi|papaya|passion|maracuja|pomegranate|granatap/, "tropical"],
  [/spice|gewürz|cinnamon|zimt|paprika pulver|curry|cumin|kreuzkümmel|salt\b|salz|pepper ground/, "spices"],
  [/sauce|soße|ketchup|mayonnaise|mayo|mustard|senf|pesto|dressing|vinegar|essig|stock|brühe|soup|suppe|hummus/, "sauces"],
];
const CO2_CAT = {meat:"pork", fish:"fishwild", dairy:"cheese", eggs:"eggs", oils:"oil", butter:"butter", fruit:"fruit", veg:"vegjar", bread:"grain", sweets:"sweets", coffee:"coffee", drinks:"juice", other:"other"};
function co2Type(it){
  if (it.ct && CO2T[it.ct]) return it.ct;
  const t = ((it.g||"") + " | " + (it.name||"")).toLowerCase();
  for (const [re, k] of CO2_RULES) if (re.test(t)) return k;
  return CO2_CAT[it.cat] || "other";
}
// kg CO2e per kg as bought → g CO2e per 100 g of the edible part, so it sums like any nutrient.
function co2Per100(it){ const v = CO2T[co2Type(it)][0], ep = it.ep > 0 && it.ep <= 1 ? it.ep : 1; return v/ep*100; }
const CO2_AVG_DAY = 4.7, CO2_GOOD_DAY = 2.8;   // kg CO2e per person and day from food in Germany: average, and with a climate-friendlier diet
function fmtKg(g){ const kg = g/1000; return (kg >= 100 ? fmtInt(kg) : kg.toLocaleString("de-DE",{maximumFractionDigits: kg >= 10 ? 0 : 1})) + " kg"; }
