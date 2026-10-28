# HXL migration notes

Journal de la migration CLT/LWC → HXL/Mosaic. Les messages d'erreur sont consignés
verbatim : c'est notre documentation de substitution.

## 0. Résumé : la recette qui marche (2026-10-14)

Ce journal est chronologique et garde les impasses. Ce qui a été retenu :

- **Org** : scratch org (`uiWidgetSettings.hxlEnabled` dans la définition) ou dev org (toggle Setup).
- **Widget** `uiWidgets/restaurantList` (§6.2) + CLT `restaurantHxlResponse` pour Agentforce (§6.3),
  bascule LWC ↔ widget par Output Rendering dans Setup.
- **MCP / Claude** : `McpServerDefinition` + CLT `restaurantSearchMcpResult` / `restaurantSearchPayload`
  (§2, §6.6), classe Apex `global`, ECA en source, clés générées par l'org (§7, §14).
- **Agentforce, test 2026-10-14 sur la dev org** (§8.1 à 8.4, conclusion : action sans `source:`, type de sortie = `complex_data_type_name` du `.agent`) : changer l'Output Rendering / Data Type
  de la sortie `restaurants` dans Setup (Agentforce Assets → Actions → Search Restaurants → Advanced
  Settings) vers `RestaurantHxlResponse` **ne change rien** à l'écran, l'agent publié affiche toujours le
  LWC. Avec Agent Script, le type de sortie est aussi porté par le `.agent` (`complex_data_type_name`),
  copie suspectée d'avoir priorité sur le GenAiFunction ; test en cours (bascule dans le `.agent` + republish).
  La liste du picker propose aussi `RestaurantSearchPayload` (filtrée sur les CLT qui référencent le type
  Apex) : rôle MCP uniquement, à ne pas choisir.
- **Claude** : connecteur branché sur le serveur MCP hébergé avec l'ECA (option « Utiliser votre propre
  client OAuth », Client ID = consumer key, pas de secret) ; Claude détecte aussi DCR sur ce serveur.
- **Abandonné** (exploration d'août 2026, retirée de ce journal) : Custom Connections (AiSurface /
  AiResponseFormat) et client Agent API headless.

## 1. Documentation officielle HXL trouvée (2026-09-01) — tout change

Guide officiel : https://developer.salesforce.com/docs/platform/hxl/guide/get-started.html
(« Headless Experience Layer Developer Guide (Beta) », non indexé par le MCP docs).
Référence métadonnées : `UiWidgetBundle (Beta)`, API 67.0+ —
https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_uiwidgetbundle.htm

### Activation = un settings, pas un pilote

Setup → Quick Find « Headless Experience Layer Settings » → toggle. En métadonnées :
`settings/UiWidget.settings-meta.xml` → `<UiWidgetSettings><hxlEnabled>true</hxlEnabled></UiWidgetSettings>`
(retrieve de l'org : valeur `false` → explique « Not available for deploy for this organization »).

### Bundle (confirme le repo communautaire)

`uiWidgets/<name>/{<name>.json, <name>.uiwidget-meta.xml, schema.json (optionnel)}`.
Composition : `{ "type": "lightning__agentforceWidget", "contentBody": { "widgetBody": { "definition": "tile/widget", "children": [] } } }`.
Bindings `{!$attrs.x}` ; `meta.if` (formules : `{!AND($attrs.a, $attrs.price < 500)}`) ;
**itération** `meta.forEach: "{!$attrs.items}"`, `forItem: "$item"`, `forIndex` — combinable avec `if`.
Composants : accordion, avatar, badge, button, callout, code, column, container, icon, image,
link, list/listItem, markdown, progress, row, separator, spacer, spinner, table, text.

### Câblage à une action Agentforce

`renderer.json` à la **racine** du LightningTypeBundle (pas dans un dossier canal) :
`"componentOverrides": { "$": { "definition": "@widget/c/<widget>", "attributes": { "<attrWidget>": "{!$attrs.<propCLT>}" } } }`.
Déployer le widget avant le CLT (ou ensemble). Puis Setup → Agentforce Assets → Actions →
sortie structurée → « Show in conversation » + « Output Rendering » = le CLT.
LWC override = dossier canal ; widget HXL = racine, multi-surface.

### Canal retour

`tile/button` → `"actions": { "click": [ { "definition": "action/sendMessage", "attributes": { "content": "…" } } ] }`.
Autre action : `action/openLink` (`url`). Le message revient au subagent, qui peut déclencher une action.

### Claude / ChatGPT / Slackbot = Hosted MCP server de l'org + MCP Apps

Étapes : classe Apex `global` + `@InvocableMethod` → deux CLT object-based taggés `"lightning:tags": ["mcp"]`
(payload : `@apexClassType/c__X$Y` ; wrapper : `actionName`, `isSuccess`, `outputValues`) →
`renderer.json` du wrapper mappe `{!$attrs.outputValues.<x>.<y>}` → widget → Setup → API Catalog →
MCP Servers → serveur custom + tool (l'action Apex) → retrieve `McpServerDefinition` → ajouter
`<resources>` (`resourceUri` = `ui://widget/lightningType/<CLT>`) + `<uiResource>` dans `<tools>` → deploy →
Activate → ECA (PKCE, JWT, scope MCP) → client (Claude Desktop/ChatGPT via URL
`https://api.salesforce.com/platform/mcp/v1/custom/<Server>` + consumer key).
Limite : pas de rendu en Block Kit Slackbot.
→ Corrige §… : l'org SERT bien l'UI à Claude (MCP Apps), aucun serveur externe requis.

## 2. CLT « rôles MCP » déployés (2026-08-31)

Créés d'après le pattern officiel (hxl-rich-ui) et déployés sans erreur sur le scratch org :

- `lightningTypes/restaurantSearchPayload/` — object-based, `"lightning:tags": ["mcp"]`,
  propriété `restaurants` → `@apexClassType/c__RestaurantService$Restaurants` ;
- `lightningTypes/restaurantSearchMcpResult/` — enveloppe `actionName` / `isSuccess` /
  `outputValues` → `c__restaurantSearchPayload`.
  Validé : le tag `mcp`, une propriété pointant sur un type Apex, et la référence CLT→CLT par nom
  passent indépendamment du gate widget. (Rappel des rôles : payload = data, wrapper = enveloppe
  qui porte le renderer.json ; le rendu lui-même reste dans le UiWidgetBundle.)
  Renderer du wrapper (`@widget/c/restaurantList`) → erreur instructive, verbatim :
  « The widget reference @widget/c/restaurantList points to a widget that is not deployed in this org.
  Deploy the widget bundle first, then try again. »
  → La résolution `@widget/<ns>/<nom>` fonctionne ; seule l'absence du widget bloque : déployer le widget d'abord.

### Correctif vocabulaire composants (2026-08-31)

La référence officielle (about-hxl-components) liste exactement 22 composants :
accordion, accordionItem, avatar, badge, button, callout, code, column, container, icon, image,
link, list, listItem, markdown, progress, row, separator, spacer, spinner, table, text.
**Ni `tile/card` ni `tile/widget` n'y figurent.** Le repo communautaire (et notre probe initial)
utilisent `tile/card` — non documenté. `tile/container` est le composant « card-like » officiel
(attributs : `borderless`, `variant` ∈ default|emphasis|info|warning|error|success).
Probe corrigé card→container. `tile/widget` reste utilisé comme racine dans l'exemple de composition
du guide (contentBody.widgetBody) — racine spéciale, pas un composant de la référence.
Release notes produit : l'article `rn_headless360` des Salesforce Release Notes (release 262).

## 3. Référence composants consolidée (lecture intégrale via .md, 2026-08-31)

Chaque page du guide a un jumeau `.md` (index : docs/llms-headless-experience-layer.txt) — lecture
quasi-verbatim, curl bloqué (403 site-wide) mais fetch outillé OK. Les 47 pages sont lues.

Composants (22) et attributs clés :

- **text** : text (requis), variant body|caption|code|h1–h6, weight, color, isItalic, isStrikethrough.
- **markdown** : source (GFM ; PAS de task-lists ni HTML inline). **code** : code, language (⚠ Agentforce : pas de coloration).
- **badge** : label, variant error|info|outline|primary|secondary|success|warning (⚠ Agentforce : dépend des hooks SLDS).
- **button** : label, variant primary|secondary|destructive, iconName, actions (click → lightning\_\_actionType).
- **row** : gap none|xs–xl, align start|center|end|stretch, justify start|center|end|between|around|evenly, isWrapped.
- **column** : gap, align, width auto|xs–xl|full|stretch (grille 12 col : xs–xl = 3–9).
- **container** (le « card » officiel) : borderless, variant default|emphasis|info|warning|error|success.
- **callout** : title (requis), description, variant default|error|info|note|success|tip|warning, iconAlt.
- **icon** : name (requis, lightning\_\_iconName), color, size xs–xl, alt. **avatar** : src|initials|iconName (≥1), shape circle|square|rounded, size (⚠ AF : xl→lg, rounded→square).
- **image** : src + alt requis, size auto|sm|md|lg|full ; formats PNG/JPEG/GIF/WebP — **SVG interdit**.
- **link** : href requis, text, underline, variant (⚠ AF : variant/underline non supportés).
- **list** (marker none|bullet|number, 1–10 items) + **listItem** (sans props ; enfants text/link/icon).
- **table** : caption+columns+rows requis ; columnType date|link|number|picklist ; isSortable/isFilterable/pagination (⚠ AF : tri/filtre/pagination à gérer manuellement).
- **progress** : label+size requis, value, max, shape linear|circular, color (⚠ AF : seul success natif).
- **spinner** : label requis. **separator** : orientation. **spacer** : size xs–xl|fill.
- **accordion**/accordionItem : title requis, subtitle, isExpanded, iconName ; comportement d'expansion laissé à la surface.
- Actions (lightning\_\_actionType) : action/sendMessage (content), action/openLink (url). Formules Salesforce dans les bindings.
- Playground : badges Beta / Developer Preview par composant.
  Correctif confirmé : PAS de tile/card (container = équivalent) ; tile/widget = racine spéciale de composition uniquement.

## 4. Traçabilité des sources produit (2026-08-31)

L'article de release notes produit `rn_headless360` (release 262) est inaccessible à tout outillage :
SPA help.salesforce.com (page d'erreur hors navigateur), non indexé par Google (seule sa meta-description
remonte : « Headless 360 features and changes are released as often as monthly »), absent de l'index MCP
docs (qui s'arrête à la release 260), PDF resources.docs 404. Seul un navigateur humain y accède.
Note : la phrase « the host caches the widget aggressively » (Apex Hours, 24/08/2026) concerne le cache
du widget MCP Apps côté Claude Desktop dans LEUR démo (workaround : ⌘Q + nouveau chat après un
handshake raté) — pas une limitation officielle de la plateforme.

## 5. Second repo communautaire : hxl-mcp-widget-sample (2026-09-10)

Source : https://github.com/hinabasfdc/hxl-mcp-widget-sample (Hiroyuki Inaba, Salesforce Japon,
28/08/2026), sources d'un billet du blog développeur japonais
(`developer.salesforce.com/jpblogs/2026/08/headless-experience-layer-custom-ui-widget-jp`, 403 hors navigateur).
Cas : carte « résumé des opportunités d'un compte » affichée dans ChatGPT / Claude via MCP.

Structure strictement identique à la nôtre (§2) : Apex `@InvocableMethod` → `GenAiFunction` → trois
LightningTypeBundles (wrapper Apex, `OutputValues`, `Result` taggés `mcp`) → `renderer.json` racine
`@widget/c/accountSummaryCard` → `UiWidgetBundle` (`widgetType` JSON) → `McpServerDefinition` avec
`<resources>`/`<uiResource>`. Rien de nouveau côté vocabulaire Mosaic.

Apports réels :

- **Prérequis org (README)** : instance « Summer '26 Patch 14.4 ou ultérieur », HXL activé, et
  « Developer Edition ou Sandbox recommandé pour la vérification ».
- **Pattern « pré-formatage en Apex »** : le widget ne consomme que des `lightning__textType`
  (`accountInitials`, `totalOpportunityCountText`, `openOpportunityAmountFormatted`, `stageSummaryText`
  concaténé). Pas de `forEach`, pas de `table` : toute la mise en forme est faite côté Apex.
  À garder en tête si l'itération Mosaic se révèle limitée sur une surface.
- **Gotcha cache MCP Apps** : le hôte cache le template par `resourceUri`. Si une modif du widget
  n'apparaît pas : « Refresh tools » côté client ; sinon dupliquer le LightningTypeBundle sous un nouveau
  nom d'API (`…ResultV2`), mettre à jour `<resourceUri>`/`<uiResource>` et ré-enregistrer le connecteur.
  Confirme (côté plateforme cette fois) la remarque Apex Hours du §4.
- Le `GenAiFunction` y sert uniquement d'enregistrement dans l'API Catalog pour le tool MCP ; aucun
  câblage à un agent Agentforce n'est montré.

### 5.1 L'article lui-même (lu via proxy r.jina.ai, publié le 24/08/2026)

Le site renvoie 403 à tout client non-navigateur ; `r.jina.ai/<url>` passe. Ce qu'il ajoute au README :

- **Beta « fin août 2026 »** (« 2026年8月後半よりベータ公開 »). Cohérent avec notre §1 (doc apparue le 01/09).
- **Le patch conditionne l'apparition du toggle**, pas le deploy : « si ce réglage n'apparaît pas, vérifier
  que l'instance est en Summer '26 Patch 14.4 ou ultérieur ».
- **`tile/icon` : `name` doit exister** (ex. `currency` n'existe pas) sinon **tout le widget crashe en
  `NullPointerException`** avec un message générique. Piège à retenir pour notre `restaurantList`
  (nos icônes : vérifier chaque nom contre `lightning__iconName`).
- **Schéma du widget non rétro-compatible** : supprimer une propriété de `schema.json` après un premier
  deploy → « Schema update contains breaking changes: … properties cannot be removed ». Conseil : garder
  les anciennes propriétés et en ajouter. À documenter dans l'article (différence nette avec le LWC, où
  changer `@api` est libre).
- **Ordre de deploy conseillé** : Apex → LightningType & UiWidget → GenAiFunction → McpServerDefinition,
  « mais un deploy groupé résout souvent les dépendances ».
- **Aucune mention d'un rendu dans Agentforce** (chat hébergé Salesforce) : l'article ne couvre que
  ChatGPT et Claude via MCP. Le widget respecte FLS et sharing (« données réelles de l'org »).
- Chaîne de rendu MCP : les `<tools>` (données) et `<resources>` (apparence) sont liés par
  `<uiResource>` = `<resourceName>` ; CSP et réglages MCP internes sont générés automatiquement.

## 6. Premier widget déployé (2026-09-10)

Dev org créée par signup pre-release : **Winter '27 Patch 4.7**, Enterprise Edition, `IsSandbox=false`.
Toggle HXL activé dans Setup, puis deploy d'un widget de test : **succès**.

### 6.1 Syntaxe d'itération, enfin sourcée

La page `guide/hxl-widget-composition.html` (lue en texte brut via `r.jina.ai`, les blocs JSON
sont perdus mais la prose est complète) documente l'objet `meta` : `if` (booléen strict, null = false),
`forEach` (collection), `forItem` (doit commencer par `$`, défaut `$Item`), `forIndex`. `if` + `forEach`
combinés = filtre par item ; `if` sur `$attrs.x` dans un `forEach` = évalué une fois pour toute la liste.
Formules : moteur Salesforce (`{!$order.subtotal * $order.taxRate}`), exemples dans le Playground `#06-formulas`.
Zips d'exemple officiels (hotelCard widget, hotelInfo CLTs, Apex) téléchargeables depuis
`resources.docs.salesforce.com/rel1/doc/en-us/static/misc/{HotelCardWidget1,HotelInfoLightningTypes1,HotelSearchResultApexClassBundle1}.zip`
— notre `uiWidgets/hotelCard` est identique à l'octet près. Aucun exemple officiel d'attribut collection.

### 6.2 Widget `restaurantList` (étape 3 du plan) — déployé

`uiWidgets/restaurantList/` : `forEach` sur `{!$attrs.restaurants}` (`forItem: "$restaurant"`), un
`tile/container` par restaurant : nom (h3) + badge `PriceRange__c`, icône `star` + `NumberOfStars__c`,
cuisine, et un `tile/button` « Book a table » → `action/sendMessage` (cf. §6.4).

Erreurs instructives du validateur (verbatim) :

- `$.properties.attributes.properties.restaurants.items: is missing but it is required`
  → un attribut `lightning__listType` exige un sous-schéma `items` (ici `lightning__objectType` avec
  les champs `Id`, `Name`, `NumberOfStars__c`, `TypeOfCuisine__c`, `PriceRange__c` en `textType`).
  Non documenté dans le guide ; c'est le validateur qui l'apprend.
- `LightningTypeBundle restaurantHxlResponse | Value too long for field: Description maximum length is:255`
  → la `description` d'un CLT est limitée à 255 caractères.
- `CustomField Restaurant__c.Address__c | Invalid data type.` → champ Address custom : l'org neuve
  n'a pas `CustomAddressFieldSettings.enableCustomAddressField` (activé par la scratch def). Ajouté en
  `settings/CustomAddressField.settings-meta.xml`, déployé seul avant le reste. Hors HXL, mais bloquant.

### 6.3 CLT « Agentforce » séparé : `restaurantHxlResponse`

Pour rester additif (l'agent continue d'utiliser `c__restaurantResponse` → LWC), nouveau CLT
`lightningTypes/restaurantHxlResponse/` : même `@apexClassType/c__RestaurantService$Restaurants`,
`renderer.json` **à la racine** → `@widget/c/restaurantList` avec `restaurants: "{!$attrs.listRestaurants}"`.
Basculer l'agent = Setup → Agentforce Assets → Actions → Search Restaurants → sortie `restaurants` →
Output Rendering = `Restaurant HXL Response` (ou `complex_data_type_name: "c__restaurantHxlResponse"`
dans le `.agent`). Les quatre CLT (LWC, HXL, payload MCP, wrapper MCP) déploient ensemble sans erreur :
la validation design-time du mapping renderer → attributs du widget passe, y compris vers un attribut liste.

### 6.4 Canal retour (étape 4) — choix de conception

`content` du `sendMessage` : `"Book a table at {!$restaurant.Name} (restaurant Id {!$restaurant.Id})"`.
Le texte revient au subagent `Restaurant_Management`, dont les instructions demandent date/heure puis
appellent `Book_Restaurant` ; l'entrée `restaurantId` (`isUserInput: false`) peut être extraite du message
par le planner. TODO(unverified) : interpolation d'un token au milieu d'un littéral (accepté au deploy,
à vérifier au rendu) ; alternative formule `{!"Book a table at " & $restaurant.Name}`.

### 6.5 État de la dev org après deploy complet de `force-app/`

**Refusé** (« Not available for deploy for this organization ») : `GenAiFunction`
(×2), `AiAuthoringBundle`, `AiResponseFormat`, `AiSurface` — Agentforce/Einstein n'est pas activé dans
l'org. Piège org non-scratch : un deploy avec une erreur est **annulé en bloc** (rollback par défaut,
contrairement au push scratch) — le rapport « 41 deployed » était trompeur, app/tabs/thème absents de
l'org. Rejoué par lots sans les types AI (`--source-dir` multiples), ou `--ignore-errors`.
Deuxième piège, HXL cette fois : dans un paquet qui contient des composants en échec, les **4 CLT
échouent en « An unexpected error occurred … ErrorId »** (aussi observé au tout premier essai quand
l'Apex échouait) alors que seuls, ils redéploient sans erreur. Le validateur CLT ne dégrade pas
proprement quand une dépendance du même paquet (GenAiFunction qui référence `c__restaurantResponse`,
ou la classe Apex) est en erreur → toujours déployer les CLT dans un lot sain. Tentative d'activation par métadonnées (`EinsteinGptSettings.enableEinsteinGptPlatform`,
`AgentPlatformSettings.enableAgentPlatform`) : même refus. Il faut activer Einstein / Agentforce dans
Setup (Einstein Setup → Turn on Einstein), si l'org pre-release y a droit, puis rejouer
`sf project deploy start --source-dir force-app`, `sf agent publish authoring-bundle …`, `post-push-source`.
Le test de rendu Agentforce (Output Rendering = `Restaurant HXL Response`) reste donc à faire ;
la partie HXL proprement dite (widget + CLT + renderers) est validée au deploy.

### 6.6 `McpServerDefinition` : déployable sans Einstein

`mcpServerDefinitions/restaurantsearchserver.mcpServerDefinition-meta.xml` (calqué sur le repo hinaba,
§5) : tool `aa:apex-RestaurantService` (`apiSource: API_CATALOG`, `toolName:
RestaurantServiceapex_RestaurantService`), `uiResource: restaurantList` → resource
`ui://widget/lightningType/c__restaurantSearchMcpResult`. **Deploy OK** alors que les `GenAiFunction`
sont refusés : l'API Catalog référence directement la classe `@InvocableMethod`, le `GenAiFunction`
n'est pas un prérequis (contrairement à ce que suggère le README hinaba). Reste côté Setup :
API Catalog → MCP Servers → Activate, External Client App (PKCE, JWT, scope MCP), puis connecteur
Claude Desktop / ChatGPT sur `https://api.salesforce.com/platform/mcp/v1/custom/restaurantsearchserver`
(cf. §1). Non testé : ce chemin permettrait de voir le widget rendu **sans Agentforce**.

Hors HXL, spécifique org non-scratch : les champs custom déployés n'ont pas de FLS pour l'admin
(en scratch org, le deploy l'accorde au profil). L'import `sf texei data import` échoue en
`INVALID_FIELD NumberOfStars__c` tant que le permset `Restaurants_Management` n'est pas assigné —
lequel ne se déploie pas (`agentAccesses` → Bot inexistant). Contournement : version du permset sans
`agentAccesses` déployée depuis un projet temporaire, assignée, puis import (`Data imported`).
Le permset complet (avec `tabSettings`/`applicationVisibilities`) exige que tabs et app soient déjà
dans l'org — déployés ensuite par lot (tabs, applications, layouts, thème, `post-push-source/settings`).

### 6.7 Reste à faire (actions Setup manuelles)

1. Activer Einstein / Agentforce dans l'org (Setup → Einstein Setup), si l'org y a droit.
2. Rejouer `sf project deploy start --source-dir force-app` (les 5 composants AI), puis
   `sf agent publish authoring-bundle --api-name Restaurant_Agent --skip-retrieve`, puis
   `sf project deploy start --source-dir post-push-source` (permset complet avec `agentAccesses`).
3. Setup → Agentforce Assets → Actions → Search Restaurants → sortie `restaurants` →
   Output Rendering = **Restaurant HXL Response** → tester « restaurants in Paris » dans le Builder ;
   cliquer « Book a table » et vérifier que le subagent enchaîne sur `Book_Restaurant` (canal retour, §6.4).
4. Voie MCP sans Agentforce : Setup → API Catalog → MCP Servers → `restaurant-search-server` → Activate ;
   External Client App ; connecteur Claude Desktop → le même widget doit s'afficher dans Claude.

## 7. Voie MCP : Claude → serveur MCP hébergé de l'org → widget (2026-09-10, soir)

Org de travail : scratch org Winter '27, démo complète déployée, agent activé. Objectif : Claude connecté via le serveur
MCP custom `restaurant-search-server` et le widget `restaurantList` rendu dans Claude (MCP Apps).

Sources officielles lues (via `r.jina.ai`) : guide HXL `hxl-mcp-server`, `hxl-mcp-setup-org`,
`hxl-mcp-setup-client`, `hxl-mcp-apex` ; guide Hosted MCP Servers `create-external-client-app`,
`claude`, `invocable-actions`, `client-connection-overview`.

### 7.1 Ce qui est fait (par métadonnées, sans Setup)

- `McpServerDefinition restaurantsearchserver` déjà dans l'org (push) : Tooling montre le tool
  `RestaurantServiceapex_RestaurantService` avec `UiResource=restaurantList` et la resource
  `ui://widget/lightningType/c__restaurantSearchMcpResult` (`McpServerToolDefinition`,
  `McpServerResourceDefinition`).
- **Classe Apex passée en `global`** (`RestaurantService`, méthode et inner classes) : la doc
  `invocable-actions` est explicite, « only Apex classes with a global method annotated
  @InvocableMethod can be exposed as MCP tools ». Le deploy du `McpServerDefinition` passait pourtant
  avec la classe `public` — le validateur ne vérifie pas ce point, c'est au runtime que ça se serait vu.
- **External Client App `HXL_Claude_MCP`** déployée par Metadata API (même
  mécanique que pour l'Agent API) : callback `https://claude.ai/api/mcp/auth_callback`, scopes **`MCP, RefreshToken`**
  (noms métadonnées de `mcp_api`/`refresh_token` — appris par l'erreur du validateur qui liste les 37
  valeurs), `isNamedUserJwtEnabled=true`, `isPkceRequired=true`, `isConsumerSecretOptional=true`
  (client desktop public), pas de client credentials. La doc dit qu'on ne peut pas créer d'ECA en scratch
  org via Setup ; par Metadata API ça passe. Consumer key générée à la main par le script de l'époque ; depuis le §14, l'org la génère.
- Activation du serveur MCP : l'objet Tooling `McpServerAccess` (`McpServerId`, `Active`) existe mais le
  POST renvoie `UNKNOWN_EXCEPTION`. Ce n'est pas la bonne porte : l'API Catalog Connect REST API l'active
  (§15).

Pièges CLI rencontrés : (1) `sf project deploy start --source-dir` refuse un dossier hors projet
(`UnsafeFilepathError … unsafe character sequences`), et le chemin reste ensuite dans le tracking local
→ `sf project reset tracking` ; (2) des `.DS_Store` dans `uiWidgets/` font planter le deploy
(`ENOTDIR: not a directory, scandir …/uiWidgets/.DS_Store`) → supprimés, `**/.DS_Store` ajouté au
`.forceignore`.

### 7.2 Reste à faire côté Setup et Claude (manuel)

1. Activer le serveur : Setup → MCP Servers → `restaurant-search-server` → **Activate**, ou par API
   (§15, ce que fait `createScratchOrg.sh`). L'URL du serveur est renvoyée par `sf agent mcp list --json` :
   `https://api.salesforce.com/platform/mcp/v1/d/<my-domain>/scratch/custom/restaurantsearchserver`
   sur un scratch org (segment `scratch`, pas `sandbox`).
2. Rester connecté à l'org dans le navigateur par défaut (l'OAuth de Claude y ouvre un onglet ; se
   déconnecter des autres orgs Salesforce avant, conseil de la doc).
3. Claude → Customize → Connectors → **+** → Add custom connector : nom libre, URL du serveur, Advanced
   settings → **OAuth Client ID** = consumer key de l'ECA (Setup → External Client App Manager → HXL Claude MCP → OAuth Settings), pas de secret.
   Connect → login Salesforce → Configure pour vérifier que le tool « Search Restaurants » est listé.
4. Prompt : « restaurants in Paris » → le tool renvoie le wrapper `c__restaurantSearchMcpResult`,
   Claude rend la resource `ui://widget/lightningType/c__restaurantSearchMcpResult` = widget
   `restaurantList`. Le bouton « Book a table » envoie un `sendMessage` dans la conversation Claude
   (§6.4) ; il n'y a pas d'action `Book_Restaurant` exposée au serveur MCP pour l'instant.
5. La doc prévient : l'ECA peut mettre jusqu'à 30 minutes à être utilisable avec `api.salesforce.com`
   (déployée à 16:22 UTC) ; et un widget modifié après un premier rendu met du temps à se rafraîchir
   côté client.

## 8. Dev org : rendu Agentforce enfin à l'écran, et trois surprises (2026-10-14)

Branche `hxl-widget` (main + widget, CLT HXL et MCP, McpServerDefinition, ECA). Deploy par lots sans erreur
(settings seuls, puis `force-app` : 41 composants), publish, post-push-source, permsets, data, activate.
Claude connecté au serveur MCP hébergé avec l'ECA : widget rendu dans Claude, champs remplis, bouton OK.

### 8.1 Output Rendering : Setup et `.agent` doivent dire la même chose, et seul Setup écrit l'action

Observations dans l'ordre :

1. Changer le Data Type / Output Rendering de la sortie `restaurants` dans Setup (Agentforce Assets →
   Actions → Search Restaurants → Advanced Settings) vers `RestaurantHxlResponse` : **aucun effet** sur
   l'agent publié, qui continue d'afficher le LWC.
2. `complex_data_type_name: "c__restaurantHxlResponse"` dans le `.agent`, deploy du bundle,
   `sf agent publish authoring-bundle` (crée une **version 2 inactive**), `sf agent activate` (première
   tentative `NoAgentsInOrgError` / `ERROR_HTTP_404` juste après le publish, OK 20 s plus tard) : widget rendu.
3. Retour au LWC : `complex_data_type_name: "c__restaurantResponse"` dans le `.agent`, deploy, publish →
   **refusé** par le validateur, verbatim :
   `Validation failed for action 'Search_Restaurants' due to the invalid value for attribute
   'complex_data_type_name' for the output parameter 'restaurants'. To fix, update the
   'complex_data_type_name' attribute value for the output parameter 'restaurants' from
   'c__restaurantResponse' to 'c__restaurantHxlResponse'.`
   Le publish compare le `.agent` à l'action telle qu'elle est dans l'org, et c'est l'action qui fait foi.
4. Redeploy du GenAiFunction depuis la source (`lightning:type: c__restaurantResponse`) : « Succeeded »
   mais composant **Unchanged**, et la retrieve montre que l'org garde `c__restaurantHxlResponse`. Même
   résultat avec une modification de `description` dans `output/schema.json` : Unchanged, rien n'est écrit.
   Le `output/schema.json` d'un GenAiFunction existant n'est donc plus modifiable par Metadata API (au
   moins une fois référencé par un agent publié) ; seul Setup le change. TODO(unverified) : idem avant
   toute publication d'agent ?

Lecture cohérente de tout ça : le type de sortie vit sur l'action (GenAiFunction, éditable dans Setup
uniquement), le `.agent` en porte une copie qui doit être identique au moment du publish, et l'agent
publié fige ce qu'il a lu au publish. D'où : un changement Setup seul n'est visible qu'après un nouveau
publish, et un publish avec un `.agent` en désaccord est refusé.

Nuance d'UI : sur la page de l'action, « Data Type » et « Output Rendering » sont deux vues du même
champ (`lightning:type` de la sortie). Choisir un CLT dans Output Rendering **remplace** le type Apex
par le CLT dans Data Type ; le type Apex brut (`@apexClassType/…`) n'est que l'état « aucun rendu ».
La liste est filtrée sur les CLT dont le schéma référence le type Apex de la sortie (d'où
`RestaurantSearchPayload`), et ne présélectionne pas toujours la valeur courante (« Select an Option »).
Non expliqué : Data Type affichait déjà `c__restaurantHxlResponse` avant tout changement dans Setup,
alors que le deploy initial et la publication v1 portaient `c__restaurantResponse`.

**Recette de bascule** (LWC ↔ widget), dans cet ordre :
1. Setup → Agentforce Assets → Actions → Search Restaurants → sortie `restaurants` → Advanced Settings →
   Output Rendering = `RestaurantResponse` (LWC) ou `RestaurantHxlResponse` (widget).
2. `.agent`, action `Search_Restaurants`, sortie `restaurants` : `complex_data_type_name: "c__restaurantResponse"`
   ou `"c__restaurantHxlResponse"`, la même valeur qu'en 1.
3. `sf project deploy start --source-dir force-app/main/default/aiAuthoringBundles`
4. `sf agent publish authoring-bundle --api-name Restaurant_Agent --skip-retrieve`
5. `sf agent activate --api-name Restaurant_Agent` (réessayer si 404 immédiat), nouvelle conversation.

Le picker de Data Type liste aussi `RestaurantSearchPayload` (tout CLT dont le schéma référence le type
Apex) : rôle MCP uniquement, forme incompatible, pas de renderer. Fuite du rôle MCP dans l'UI Agentforce.

### 8.2 Un SObject ne se sérialise pas pareil selon la surface

Widget rendu dans Agentforce avec le `.agent` basculé, mais **tous les bindings `$restaurant.*` vides**
(nom, prix, étoiles, cuisine, et le `sendMessage` donnait « Book a table at  (restaurant Id ) »), alors
que `forEach` itérait bien sur les 3 restaurants et que le même widget est complet dans Claude.
Cause : dans Agentforce, les `Restaurant__c` de la sortie d'action arrivent au format record de l'UI API
(le LWC `restaurantDetails` ne lit que `obj.id` en minuscule puis ré-hydrate via `getRecords`, c'est
pour ça qu'il marchait), alors que le serveur MCP hébergé envoie le JSON plat de l'action invocable
(`Id`, `Name`, …). TODO(unverified) : forme exacte côté Agentforce (`fields.Name.value` ?), non observée.
Correctif : `RestaurantService.Restaurants.listRestaurants` devient une `List<Restaurant>` de DTO plats
(`id`, `name`, `stars`, `cuisine`, `priceRange`), sérialisés pareil partout. Le LWC reste compatible
(il n'utilise que `id`). Leçon générale : pour un widget multi-surface, sortir des DTO, jamais des SObjects.

### 8.3 Le schéma d'un widget publié n'accepte que des ajouts

Renommer les propriétés de `items` dans `uiWidgets/restaurantList/schema.json` → refus verbatim :

```
UiWidgetBundle restaurantList | Schema update contains breaking changes:
You can’t delete the $.properties.attributes.properties.restaurants.items.properties.Id property with value {"title":"Record Id","lightning:type":"lightning__textType"}.
You can’t delete the $.properties.attributes.properties.restaurants.items.properties.Name property with value {...}.
...
```

Et sur une org non-scratch, l'échec du widget a annulé tout le lot (Apex et CLT « Changed » dans le
rapport, mais rollback). Contournement : garder les anciennes propriétés dans le schéma, marquées
« deprecated » dans leur `description`, et ajouter les nouvelles ; deploy OK. Pour un schéma propre,
il faut supprimer le widget de l'org (destructive changes) et le recréer.

### 8.4 Sortie de crise : l'action vit dans le `.agent`, plus de GenAiFunction

L'Output Rendering de l'action ne pouvait plus être modifié dans Setup (liste vide). Le GenAiFunction
`Search_Restaurants` a été supprimé dans Setup. La référence Agent Script des actions
(`ascript-ref-actions`) ne connaît que `target` (obligatoire) ; `source:` n'y figure pas, c'était un
héritage de la migration depuis l'ancien format Bot. Test : ligne `source: "Search_Restaurants"` retirée
du `.agent`, deploy du bundle, `sf agent publish authoring-bundle` → **succès**, `sf agent activate` →
version 3 active, et `sf org list metadata --metadata-type GenAiFunction` → **aucun** : le publish ne crée
pas d'asset action, l'action est interne à l'agent. Plus de double déclaration, donc plus de désaccord
Setup / `.agent` possible : `complex_data_type_name` est la seule source du type de sortie.
MCP : aucun impact, le `McpServerDefinition` référence l'Apex via l'API Catalog (`aa:apex-RestaurantService`).
Conséquence pour le repo : `genAiFunctions/Search_Restaurants` sort de `force-app` (sinon un deploy
complet le recrée), README et CLAUDE.md mis à jour. Sur une org où l'action existe déjà, la supprimer
d'abord dans Setup, ou garder `source:` et accepter la contrainte de concordance.

## 9. Le bundle « hxl-widget-authoring » du Playground et le repo public sf-skills (2026-10-14)

Zip téléchargeable depuis le HXL Playground, déposé dans `.claude/skills/hxl-widget-authoring/` : un **skill au format
Claude Code** (`SKILL.md` + `references/` + `api/v68.0/`), version 0.0.1, sous Terms of Use Salesforce
(les Terms autorisent la redistribution si le fichier LICENSE accompagne la copie ; choix fait le 2026-10-15 de ne pas le committer, dossier `.claude/` ignoré). Contenu :
méta-schéma du `schema.json` de widget, schéma JSON du payload de widget, un `.md` et un `.schema.json` par
composant `tile/*` (22 composants, index dans `component-index.md`), `expressions.md`, `icons.md` (liste
fermée, `star` et `calendar` y sont), `common-components.md`.

Ce qu'il apprend sur notre widget :

- **Méta-schéma** : un `lightning__objectType` exige `properties` **et** `additionalProperties: false` ; un
  `lightning__listType` exige `items` (déjà appris du validateur, §6.2). Notre `schema.json` est
  invalide sur les deux objets (`attributes` et `items`) : validé en local avec `ajv` (node_modules de
  Jest), le validateur de deploy ne l'exige pas. Ajouter `additionalProperties: false` sur le widget
  déployé est **refusé** comme breaking change, verbatim : `false is an invalid value for
  $.properties.attributes.properties.restaurants.items.additionalProperties. You can only change its
  value if its previous value didn't equal true. Otherwise, you can delete the keyword.` (absent = true).
  Donc même un resserrement du contrat exige la recréation du widget (§8.3) ; source remise à l'état
  déployé en attendant, cible pour la recréation : `additionalProperties: false` aux deux niveaux + `items`
  en `@apexClassType` (ci-dessous) + suppression des propriétés dépréciées.
- **Payload** : `restaurantList.json` valide contre `widget-payload.schema.json` (structure seulement).
- **Actions GA** : `action/sendMessage` (`content` obligatoire, asynchrone, « consomme un tour »),
  `action/openLink` (`url`, `target` `_blank|_self`, synchrone), `action/toggleVisibility` (sur un
  `tile/container` avec `id`). Rien d'autre. Un bouton sans `actions` est rendu désactivé.
- `tile/table` existe avec colonnes typées et actions `click` par colonne : alternative à notre liste de
  cartes, à essayer.

Le `SKILL.md` renvoie au repo public `github.com/forcedotcom/sf-skills` (skills `platform-widget-generate`,
`platform-custom-lightning-type-generate`, `platform-lightning-type-widget-coordinate`,
`platform-mcp-tool-widget-coordinate`). Lus via WebFetch :

- `schema-from-lightning-type.md` : une `List<InnerClass>` Apex se déclare dans le widget comme
  `"lightning:type": "lightning__listType", "items": { "lightning:type": "@apexClassType/ns__Outer$Inner" }`,
  sans redéclarer les champs. Pour nous : `items` → `@apexClassType/c__RestaurantService$Restaurant`,
  à faire lors de la recréation propre du widget (§8.3), puisque changer `items` est un breaking change.
  Les noms de champs du widget doivent être **exactement** ceux de l'Apex (pas de renommage, pas de champ
  calculé) : confirme le choix DTO de §8.2, et interdit implicitement les SObjects comme items (aucune
  règle de mapping n'est donnée pour eux).
- `platform-mcp-tool-widget-coordinate` : confirme nos deux CLT MCP (enveloppe `actionName` / `isSuccess` /
  `outputValues`, réponse miroir de la classe `@InvocableVariable`, `lightning:tags: ["mcp"]` sur les deux,
  renderer dans l'enveloppe **à la racine**, bindings `{!$attrs.outputValues.<champ>}`). Découverte de la
  forme via `sf api request rest '/services/data/vXX/actions/custom/apex/<Action>'` (sorties uniquement).
  Limitation beta : seul le premier élément de `content[]` est modélisé.
- `platform-custom-lightning-type-generate` : dossiers canal `lightningDesktopGenAi/`, `lightningMobileGenAi/`,
  `enhancedWebChat/`, `experienceBuilder/` ; renderer racine = rendition widget. **Aucune règle de priorité
  documentée** entre renderer racine et renderer de canal dans un même bundle (TODO(unverified), §« un seul
  CLT »). Un CLT Apex ne contient que `title`, `description`, `lightning:type` (pas de `type`/`properties`).
- Aucun des quatre skills ne couvre `complex_data_type_name` / Agent Script ni l'Output Rendering : nos
  constats §8.1 et §8.4 restent de première main.

## 10. Recréation propre du widget sur la dev org (2026-10-15)

Objectif : sortir les cinq propriétés dépréciées du `schema.json` du widget (§8.3) et ajouter
`additionalProperties: false` sur `attributes` et `items` (§9), deux changements refusés comme
breaking changes sur un widget publié. Seule voie : supprimer le widget de l'org et le recréer.

Recette qui a marché, sans toucher au `McpServerDefinition` ni à l'agent :

1. `sf project deploy validate` avec un `destructiveChangesPre.xml` contenant le seul
   `UiWidgetBundle restaurantList` → refus verbatim :
   `This UI Widget is referenced elsewhere in Salesforce. : The UI Widget Restaurant List is used in
   restaurantSearchMcpResult. Remove the reference before deleting.` (idem pour `restaurantHxlResponse`).
   Le `McpServerDefinition` (`uiResource` / `resourceUri` vers le CLT) n'est pas listé comme bloquant.
2. Lever les références sans supprimer les CLT : déplacer les deux `renderer.json` hors du repo et
   redéployer les deux bundles `restaurantHxlResponse` et `restaurantSearchMcpResult` (`--source-dir`).
   Le deploy d'un `LightningTypeBundle` remplace le bundle entier : le renderer absent en source est
   retiré de l'org (« Changed », un seul fichier `schema.json` dans le rapport).
3. Revalider : plus d'erreur de référence. Le `validate` échoue alors sur
   `Average test coverage across all Apex Classes and Triggers is 0%, at least 75% test coverage is
   required` : `sf project deploy validate` force `RunLocalTests` même hors production. Exécuter la
   suppression avec `sf project deploy start --pre-destructive-changes … --manifest <package.xml vide>`
   (NoTestRun par défaut sur une org non-prod) → `Deleted UiWidgetBundle restaurantList`.
4. Réécrire `schema.json` (cinq propriétés `id`, `name`, `stars`, `cuisine`, `priceRange`,
   `additionalProperties: false` aux deux niveaux) et redéployer le widget → `Created`, nouvel Id
   (`1idbm…CpBAAU` à la place de `1idbm…BptAAE`).
5. Remettre les deux `renderer.json` et redéployer les deux CLT → `Changed` (renderer + schema).
   Contrôle : un nouveau `validate` de suppression est refusé pour les deux mêmes références, preuve que
   les CLT pointent sur le widget recréé.

Choix sur `items` : le méta-schéma du bundle Playground (`widget-schema.meta.schema.json`) ferme
`lightning:type` sur les six types standards ; `@apexClassType/…` en `items` (doc sf-skills, §9) n'y
figure pas. Comme chaque changement d'`items` coûte une recréation, le widget garde des `items`
explicites, valides contre le méta-schéma, aux noms exactement ceux du DTO Apex. TODO(unverified) :
`items` en `@apexClassType/c__RestaurantService$Restaurant`, à essayer sur un widget jetable.

Non retesté dans cette session : rendu Agentforce (Output Rendering = `Restaurant HXL Response`) et rendu
dans Claude via le connecteur MCP. Le serveur MCP n'a pas été redéployé, son activation Setup devrait
être intacte.

Testé ensuite dans le panneau Agentforce : rendu OK.

## 11. Canal retour depuis le LWC : `lightning/accApi` (2026-10-15)

Question : la modal LWC de réservation peut-elle, comme le `action/sendMessage` du widget, renvoyer un
message à l'agent au lieu de réserver en silence ? Réponse : oui, via le module documenté
`lightning/accApi` (Agentforce Conversation Client API, API 59+, panneau natif de Lightning Experience
uniquement) : `execute(utterance, botId)` envoie un texte « comme si l'utilisateur l'avait tapé ». Doc :
https://developer.salesforce.com/docs/platform/accsdk/guide/acc-api.html. Points de la doc qui comptent :
`botId` obligatoire pour `execute` (optionnel seulement pour `open`), pas de retour de la réponse de l'agent
au composant, file d'exécution séquentielle, utterances en langage naturel uniquement (pas d'appel
d'action par nom).

Ce que le LWC ne sait pas : la cible `lightning__AgentforceOutput` ne fournit que `@api value` et les
propriétés du `targetConfig`, toutes issues de la sortie de l'action. Aucun contexte (agent, session).

Tests, sur l'agent en rendu LWC (`c__restaurantResponse`) :

1. `execute(utterance)` **sans `botId`** : la promesse ne rejette pas (aucune erreur côté composant), mais
   le panneau tombe en erreur, console `COPILOT_O11Y` : `Something went wrong. Refresh and try again.`
   (×2). Rien dans le fil. Piste abandonnée.
2. `execute(utterance, botId)` avec le `botId` résolu à l'exécution par Apex
   (`AgentforcePanelController.getBotId('Restaurant_Agent')`, `SELECT Id FROM BotDefinition WHERE
   DeveloperName = …`, préfixe `0Xx`) : **succès**. Toast côté LWC, message
   `Book a table at Le Pré Catelan (restaurant Id a01…) on 2026-10-15 at 10:00` affiché dans le fil comme
   message utilisateur, réponse de l'agent (en texte : pas encore d'action de réservation).

Design retenu : la modal ne réserve pas, elle **demande** à l'agent (mêmes trois surfaces, un seul chemin
de réservation, à implémenter côté agent : action `Book_Restaurant`, cf. commit `98cb116` de la branche
d'exploration, à porter sans GenAiFunction). `restaurantBooking` émet maintenant `{date, time}` à chaque
changement de jour ou de créneau (avant : l'heure seule).

Limite restante : l'API name de l'agent est une constante dans la modal. Piste pour le rendre
dynamique par agent : chaque agent passe son API name en entrée fixe de l'action et l'Apex le renvoie
dans la sortie (TODO(unverified) : entrée à valeur littérale en Agent Script).

Jest : `lightning/accApi` n'est pas stubbé par sfdx-lwc-jest, mock ajouté dans
`force-app/test/jest-mocks/lightning/accApi.js` + `moduleNameMapper`. Échec préexistant et indépendant :
`lightning/modal` n'est pas stubbé non plus, les suites `restaurantBookingModal` et `restaurantDetails`
échouent au `import`.

## 12. Réservation sur les trois surfaces : `BookRestaurantService` (2026-10-16)

Portage de l'action d'août (commit `98cb116` de la branche d'exploration) au format sans GenAiFunction, plus
une entrée LWC, pour que les trois surfaces (modal LWC, widget HXL dans Agentforce, widget dans Claude)
aboutissent au même insert `Booking__c`.

- **Apex** `BookRestaurantService` (`global with sharing`) : logique unique `createBooking(restaurantId,
  Datetime)` ; `@AuraEnabled bookFromComponent(restaurantId, 'YYYY-MM-DD', 'HH:mm')` qui combine date et
  heure dans le fuseau de l'utilisateur (`Datetime.newInstance(Date, Time)`, règle le point fuseau horaire) ;
  `@InvocableMethod bookRestaurant` qui parse l'ISO 8601 envoyé par le planner. `restaurantId` et
  `bookingDateTime` tous deux `required=true`, descriptions qui disent où trouver l'Id (message du bouton)
  et de demander date/heure si absentes : c'est ce schéma que Claude lit côté MCP.
- **Agent Script** : action `Book_Restaurant` (`target: "apex://BookRestaurantService"`,
  `require_user_confirmation: True`, `restaurantId` en `is_user_input: False`), instructions du subagent
  complétées. Deploy du bundle, `sf agent publish authoring-bundle --skip-retrieve`, `sf agent activate` →
  **version 8** active (la version précédente, en LWC, avait été éditée dans Agent Builder : bundle
  `Restaurant_Agent_6` côté org, seule différence avec la source = la ligne `complex_data_type_name`).
- **MCP** : second `<tools>` dans `restaurantsearchserver` → `aa:apex-BookRestaurantService`, sans
  `uiResource`, `readOnly`/`idempotent`/`destructive` à `false`. Deux TODO(unverified) de la veille levés :
  l'API Catalog expose la classe **immédiatement** après son deploy
  (`GET /services/data/v68.0/actions/custom/apex/BookRestaurantService` : 2 inputs required, 2 outputs), et
  le redeploy du `McpServerDefinition` **conserve l'activation** (Tooling `McpServerAccess.Active = true`
  après deploy). Reste à vérifier côté Claude que le nouveau tool apparaît sans reconnecter le connecteur.

**Modal LWC, trois modes de démo** (split button `lightning-button-group` + `lightning-button-menu`,
mode mémorisé en `sessionStorage`, disponible sous LWS car partitionné par namespace, doc
`lws-local-storage`) :

| Mode | Effet | Ce que l'agent sait |
|---|---|---|
| `lwc` | insert Apex, rien vers l'agent | rien (sauf via une action de lecture des données) |
| `lwcNotify` | insert Apex puis `execute("FYI, I just booked… do not book again")` | une utterance utilisateur, pas un événement |
| `agent` | `execute("Book a table at …")`, pas d'insert | tout : c'est lui qui réserve, avec confirmation |

Le widget HXL n'a pas ce choix : `sendMessage`, `openLink`, `toggleVisibility` seulement, donc toujours le
mode `agent`. Il n'existe aucune API pour injecter un message système ou un résultat d'action dans le
panneau : « informer l'agent » depuis l'UI est un détournement d'utterance, visible dans le fil comme si
l'utilisateur l'avait tapé.

### 12.1 Liens, confirmation et Trusted URLs (2026-10-16, suite)

- `execute()` **attendu** par la modal : la promesse ne se résout qu'après le traitement de l'utterance
  par le panneau (file séquentielle), donc après la réponse de l'agent. La modal restait ouverte tout
  le tour. Passé en fire-and-forget, fermeture immédiate.
- Parse ISO sans fuseau : `2026-10-16T10:00:00` envoyé par le planner était lu en UTC par
  `JSON.deserialize` (point fuseau horaire). `BookRestaurantService.parseIsoDateTime` reconstruit la date dans
  le fuseau de l'utilisateur quand il n'y a ni offset ni `Z`. Vérifié : 10:00 Paris stocké 08:00 UTC.
- Écran Confirm natif : phrase générée + liste brute des entrées avec leurs `label` du `.agent`. Labels
  rendus lisibles (« Restaurant Id », « Booking date and time »). Aucune option Agent Script connue pour
  masquer une entrée (TODO(unverified) : éditeur custom `lightning__AgentforceInput`).
- Lien vers la réservation dans la réponse de l'agent, trois essais :
  1. sortie `bookingId: string` + `complex_data_type_name: "lightning__recordIdType"` : accepté au
     deploy et au publish, **aucun rendu lien** ; le modèle a inventé `https://salesforce.rel/<id>`.
  2. sortie `bookingUrl` (URL complète construite en Apex, `…my.salesforce.com/lightning/r/…`) :
     affichée **`URL_Redacted`**. Doc « Trust and Agentforce » : l'agent applique l'allowlist
     **Trusted URLs** à ses réponses, toute URL hors allowlist est remplacée par `URL_Redacted`, et le
     plan canvas signale l'URL bloquée. Le domaine Lightning de l'org (`…lightning.force.com`) n'est
     **pas** implicitement autorisé : même résultat.
  3. `CspTrustedSite` pour le domaine Lightning de l'org (contexte All, connect-src), déployé depuis
     `tmp-hxl-trusted/` (gitignored : domaine spécifique à l'org). Résultat à confirmer.
     Depuis le 2026-10-28, `createScratchOrg.sh` le génère depuis `sf org display --json` et le déploie
     après `force-app/`. Les widgets, eux, disposent de `{!$meta.env.orgUrl}` (bundle Playground).
- Toast LWC : lien via `messageData` + `NavigationMixin.GenerateUrl` (doc Platform Show Toast Event),
  supprimé en mode `agent` (le message est déjà dans le fil), gardé en vert pour les deux modes LWC.
- Données : dix `Booking__c` de test purgés (`sf data delete bulk`), dont 5 sur le même créneau.

## 13. Disponibilités : une source, trois surfaces (2026-10-16)

HXL n'a **aucun composant de saisie** (22 composants `tile/*`, tous d'affichage ; interactions = clic sur
`tile/button`, `tile/link`, cellules de `tile/table` ; actions `sendMessage`, `openLink`,
`toggleVisibility` ; `meta.if` sur un booléen, pas de négation). Choisir un horaire passe donc par un
aller-retour avec le modèle. Option retenue : action de disponibilités + widget de créneaux.

- **Apex** `RestaurantAvailabilityService` (`global`) : créneaux de référence (constante, 12:00-13:30 et
  19:00-21:00) moins les `Booking__c` du jour (bornes du jour dans le fuseau utilisateur, heures prises
  via `format('HH:mm')`). DTO `Availability` (`restaurantId`, `restaurantName`, `bookingDate`,
  `bookingDateLabel`, `hasSlots`, `hasNoSlots`, `slots[].startTime`). Entrée LWC `getSlots`
  **non cacheable** (la dispo change à chaque réservation) ; invocable `getAvailability` avec Id **ou**
  nom (LIKE) et date requise `YYYY-MM-DD`.
- **Garde serveur** dans `BookRestaurantService.createBooking` : créneau déjà pris → `BookingException`
  avec la référence existante ; relayée par la modal (rouge), l'agent et Claude (`confirmationMessage`).
  Plus champ **`Booking__c.SlotKey__c`** unique (Id restaurant + `formatGmt('yyyy-MM-dd\'T\'HH:mm')`),
  rempli par l'Apex ; `DUPLICATE_VALUE` attrapé et converti en message « réservé par quelqu'un d'autre ».
  FLS des champs `Booking__c` ajoutée au permset (piège : un seul bloc `fieldPermissions`, sinon
  « Element fieldPermissions is duplicated at this location »).
- **Widget** `uiWidgets/restaurantSlots/` : titre, date, `tile/row isWrapped` de `tile/button` en
  `forEach` sur `slots`, chaque bouton → `sendMessage("Book a table at <nom> (restaurant Id <id>) on
  <date> at <heure>")` ; texte « No availability » sous `meta.if hasNoSlots`. Schéma conforme au
  méta-schéma (`additionalProperties: false` aux deux niveaux) dès la création.
- **CLT** : `restaurantAvailability` (Agentforce, `@apexClassType/c__RestaurantAvailabilityService$Availability`,
  renderer racine → widget, 7 attributs mappés un à un) ; `restaurantAvailabilityMcpResult` +
  `restaurantAvailabilityPayload` (rôle MCP, `lightning:tags: ["mcp"]`, bindings
  `{!$attrs.outputValues.availability.<champ>}`).
- **Agent** : action `Get_Availability`, sortie `availability` en `c__restaurantAvailability`, instructions
  (« ne pas lister les créneaux en texte, ils sont affichés »). Publish → **version 12** active. L'agent
  en rendu LWC pour la liste et HXL pour les créneaux : les deux cohabitent dans le même agent.
- **MCP** : troisième tool `aa:apex-RestaurantAvailabilityService` (`readOnly`, `idempotent`) avec
  `uiResource restaurantSlots` → `ui://widget/lightningType/c__restaurantAvailabilityMcpResult`. API
  Catalog : `bookingDate` required, `restaurantId`/`restaurantName` optionnels, `availability` complexe.
- **LWC** `restaurantBooking` : fini les neuf créneaux en dur ; appel impératif à `getSlots` à l'ouverture
  et à chaque changement de jour, spinner, état vide, erreur, sélection réinitialisée (événement
  `selected` avec `detail: null`).

À tester : widget de créneaux dans Agentforce et dans Claude, clic créneau → confirmation → réservation,
refus d'un doublon, modal LWC alimentée par l'Apex.

## 14. External Client App en source, clés générées par l'org (2026-10-28)

L'ECA `HXL_Claude_MCP` était créée par un script qui fabriquait une consumer key et un secret aléatoires,
écrivait les 4 fichiers dans un dossier temporaire, déployait, et gardait la key dans un `.env` gitignored.
Vérifié sur un scratch org neuf : les 4 fichiers vivent très bien dans `force-app/`, à condition de committer
`ExtlClntAppGlobalOauthSettings` **sans** `consumerKey` ni `consumerSecret`. Doc (« Deploy the External
Client App OAuth Plugin ») : « a new OAuth consumer is created. Fields like consumerKey and consumerSecret
are generated ». Mesuré :

- deploy 1 des 4 fichiers → `Succeeded`, l'org génère une key `3MVG9…` ;
- redeploy à l'identique → `Succeeded`, **même key** : un `sf project deploy start` de `force-app/` ne casse
  pas le connecteur Claude ;
- le retrieve de `ExtlClntAppGlobalOauthSettings` renvoie la key mais **pas** le secret (secret optionnel,
  client public PKCE).

L'avertissement de la référence métadonnées (« must not be added to source control ») vise le fichier
une fois rapatrié avec ses clés ; ne pas le retrieve dans `force-app/`. La key n'est pas exposée par le
Tooling API (`ExtlClntAppGlobalOauthSettings` absent, `ExtlClntAppOauthSettings` ne porte que les scopes) :
elle se lit dans Setup → External Client App Manager → HXL Claude MCP → OAuth Settings, ou par retrieve dans
un dossier temporaire. Elle ne sert qu'au connecteur Claude, de toute façon manuel.

## 15. Activation du serveur MCP par API (2026-10-28)

Le `McpServerDefinition` se déploie inactif et le journal tenait l'activation pour « Setup uniquement »
(§2 : `McpServerAccess` en Tooling → `UNKNOWN_EXCEPTION`). La doc « API Catalog Connect REST API »
(GA juin 2026, exemple « Create a Custom Salesforce-Hosted MCP Server ») donne la porte :

- `POST /services/data/vXX.0/api-catalog/mcp-servers/{id}/activate` → `204 No Content`, idempotent ;
  `…/deactivate` pour l'inverse (obligatoire avant de changer les assets d'un serveur actif).
- Base **sans** `/connect` : `/services/data/v68.0/connect/api-catalog/...` répond `NOT_FOUND`. Le chemin
  vient de `@salesforce/agents/lib/apiCatalog.js`, utilisé par `sf agent mcp *` (developer preview).
- L'id (`1g1…`) et l'URL du serveur viennent de `sf agent mcp list --json` (`active`, `serverUrl`).
  `sf agent mcp update` ne sait pas activer (label, description, URL, auth seulement).
- Vérifié sur scratch org : `active: false` → POST → `204` → `active: true` ; second POST → `204`.
- Avec `sf api request rest`, un POST exige `--body` (ici `'{}'`), sinon « No 'mode' found in 'body' ».

Ce qui reste manuel pour la démo MCP : lire la consumer key de l'ECA dans Setup et créer le connecteur
dans Claude.
