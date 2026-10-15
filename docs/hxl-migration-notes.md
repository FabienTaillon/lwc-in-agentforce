# HXL migration notes

Journal de la migration CLT/LWC → HXL/Mosaic. Les messages d'erreur sont consignés
verbatim : c'est notre documentation de substitution.

## 0. Résumé : la recette qui marche (2026-10-14)

Ce journal est chronologique et garde toutes les impasses. Ce qui a été retenu sur la branche
`hxl-widget` (le reste de l'exploration est sur `headless-experience-layer`) :

- **Org** : une dev org (signup réel), HXL activé dans Setup ; les scratch orgs ne provisionnent pas
  le workspace `DefaultWidgetSpace` (§16). Attendre 2-3 min après l'activation avant le premier deploy.
- **Widget** `uiWidgets/restaurantList` (§15.2) + CLT `restaurantHxlResponse` pour Agentforce (§15.3),
  bascule LWC ↔ widget par Output Rendering dans Setup.
- **MCP / Claude** : `McpServerDefinition` + CLT `restaurantSearchMcpResult` / `restaurantSearchPayload`
  (§11, §15.6), classe Apex `global`, ECA via `scripts/hxl/setup-claude-mcp-app.sh` (§17).
- **Agentforce, test 2026-10-14 sur la dev org `devorg-2026`** (§18.1 à 18.4, conclusion : action sans `source:`, type de sortie = `complex_data_type_name` du `.agent`) : changer l'Output Rendering / Data Type
  de la sortie `restaurants` dans Setup (Agentforce Assets → Actions → Search Restaurants → Advanced
  Settings) vers `RestaurantHxlResponse` **ne change rien** à l'écran, l'agent publié affiche toujours le
  LWC. Avec Agent Script, le type de sortie est aussi porté par le `.agent` (`complex_data_type_name`),
  copie suspectée d'avoir priorité sur le GenAiFunction ; test en cours (bascule dans le `.agent` + republish).
  La liste du picker propose aussi `RestaurantSearchPayload` (filtrée sur les CLT qui référencent le type
  Apex) : rôle MCP uniquement, à ne pas choisir.
- **Claude** : connecteur branché sur le serveur MCP hébergé avec l'ECA (option « Utiliser votre propre
  client OAuth », Client ID = consumer key, pas de secret) ; Claude détecte aussi DCR sur ce serveur.
- **Abandonné** : Custom Connections (AiSurface / AiResponseFormat, §3-5), client Agent API headless
  (§6bis), action `Book_Restaurant` (§5), scratch defs HXL (§10.3, §10.5).

## 1. Environnement & disponibilité

- **2026-08-30** — Branche `headless-experience-layer`, scratch org
  `lwc-in-agentforce-headless-experience-layer` (Developer edition, API 67.0,
  créé le jour même, expire 2026-09-06).
- Baseline vérifiée : Bot `Restaurant_Agent` présent, BotVersion `Active`.
  Données : `data/1-Restaurant__c.json` importé via `sf data import tree --files`
  (le format texei est compatible tree import ; le plugin texei n'était pas installé) —
  5 restaurants, tous à **Porto** (pas Paris : adapter les prompts de test).
- Page officielle https://www.salesforce.com/headless/agentic-experience-layer/ :
  **HTTP 403** au fetch automatisé (2 tentatives, 2026-08-30) — protection bot.
  À consulter manuellement dans un navigateur si besoin.
- Statut HXL (source : article Apex Hours) : beta fin juillet 2026, rollout orgs
  début août 2026, GA prévue Dreamforce 2026.
- Gate de déploiement : voir §8.

### Verdict du gate (2026-08-30) — et PIVOT

- `UiWidgetBundle` n'apparaît PAS dans `sf org list metadata-types` (214 types).
- Déploiement d'un squelette (copié verbatim du repo communautaire) →
  **« Not available for deploy for this organization »** (voir §8) : la plateforme
  CONNAÎT le type (il est adressé comme `UiWidgetBundle`), mais l'org n'est pas
  provisionnée pour le pilot. API max de l'org : 67.0 = notre `sourceApiVersion`,
  donc pas de retry possible à une API supérieure. Le squelette est archivé dans
  `docs/hxl-probes/uiWidgets/` (retiré de `force-app/` pour ne pas casser les deploys).
- **PIVOT** : l'org expose en revanche `AiSurface` (+ enfants `AiSurfaceInstruction`,
  `AiSurfaceInput`) et `AiResponseFormat` (+ `AiResponseFormatIstr`) — c'est la couche
  **« Custom Connections »**, OFFICIELLEMENT documentée
  (developer.salesforce.com/docs/ai/agentforce/guide/custom-connections.html),
  supportée en scratch org, API ≥ 66. C'est le fondement org-side du « headless » :
  - `AiResponseFormat` : schéma JSON (`input`) dans lequel l'agent mappe sa réponse ;
    le client rend le JSON comme composant UI. Les schémas peuvent contenir des
    **tableaux** (exemple officiel `AcmeChatChoices`) → le « problème de la liste »
    disparaît. Champs bonus : `invocationTarget`/`invocationTargetType` (lien vers une
    action invocable — à sonder).
  - `AiSurface` (`surfaceType: Custom`) : la connexion + instructions + refs vers les
    response formats. Convention de nommage : suffixe `_{surfaceId}` (chaîne libre).
  - Câblage agent : entrée `plannerSurfaces` dans le `GenAiPlannerBundle` ;
    côté client : Agent API `/sessions` avec `"surfaceConfig": {"surfaceType": "Custom"}` ;
    réponse : tableau `result[]` avec `type: "SURFACE_ACTION__<format>"` et `value` = JSON.
  - Ordre de déploiement : `AiResponseFormat` AVANT `AiSurface`.
- La migration continue donc sur la route Custom Connections ; le Mosaic/UiWidgetBundle
  reste documenté ici comme cible future (GA Dreamforce 2026).

## 2. Vocabulaire Mosaic vérifié

Source : repo communautaire `Lakshmikanth-Paruchuru/hxl-agentic-experience-layer`
@ `3278320` (MIT), cloné le 2026-08-30. Détail complet dans
[mosaic-examples/README.md](mosaic-examples/README.md). Points saillants :

- Type de métadonnées : `UiWidgetBundle`, dossier `uiWidgets/<name>/`, 3 fichiers.
- Enveloppe org : `type: lightning__agentforceWidget` → `contentBody.widgetBody`
  (`definition: tile/widget`). Bindings `{!$attrs.x}` résolus contre `schema.json`.
- `meta.if` vérifié (bloc absent de l'arbre si faux).
- `sourceApiVersion` du repo communautaire : **65.0** → le type existait déjà à l'API 65 ;
  notre 67.0 ne devrait pas être un obstacle.

## 3. Câblage surface ↔ agent — RÉSOLU (route Custom Connections)

Constat 2026-08-30 : **aucune** trace de câblage widget ↔ GenAiFunction/LightningTypeBundle
dans le repo communautaire (leur bundle n'est jamais déployé ; la démo passe par MCP/Claude).
Le câblage documenté et **vérifié en scratch org** est celui des Custom Connections :

1. Déployer `aiResponseFormats/*` puis `aiSurfaces/*` (dans `force-app/`, source-friendly).
2. Récupérer le `GenAiPlannerBundle` généré (`Restaurant_Agent_vN`), y insérer
   `plannerSurfaces` (ordre alphabétique des éléments : entre `masterLabel` et
   `plannerType`), redéployer. **Recette exacte obligatoire** (voir §8 pour les échecs) :
   - agent **désactivé** pendant le deploy (sinon « Cannot update record as Agent is Active ») ;
   - déployer le XML du bundle **+ `localActions/`**, mais **SANS** les dossiers
     `agentScript/` et `agentGraph/` (leur présence → gack serveur ; leur absence
     totale, i.e. XML seul → **destructif**, les schémas d'action sont effacés et
     l'agent est cassé, cf. §8) ;
   - script répétable : `scripts/hxl/wire-surface.sh`.
3. Réactiver avec `--version N` (deux versions de bot après un republish ;
   sans le flag la commande devient interactive).
4. Round-trip vérifié : le serveur ajoute `adaptiveResponseAllowed=true` dans
   `plannerSurfaces` (champ non documenté dans le guide).

⚠️ Chaque `sf agent publish authoring-bundle` régénère un NOUVEAU planner
(`_v2`, `_v3`…) SANS le câblage : rejouer `scripts/hxl/wire-surface.sh` après
chaque publish. C'est LA différence opérationnelle majeure avec le pattern
CLT/LWC (où le lien schema→renderer vit dans le LightningTypeBundle, versionné).

## 4. Rendu d'une liste — RÉSOLU (deux voies)

Constat 2026-08-30 : aucun répéteur/itérateur dans l'exemple Mosaic communautaire
(bindings scalaires plats uniquement). Mais sur la route Custom Connections le
problème disparaît, deux fois :

1. **Schéma JSON libre** : l'`input` d'un `AiResponseFormat` est un JSON Schema
   arbitraire, tableaux inclus (`restaurants: array of objects`) — cf.
   `aiResponseFormats/RestaurantList_RestoHXL1`.
2. **Sortie CLT hydratée (découverte majeure)** : via l'Agent API, la réponse
   d'un tour qui a exécuté `Search_Restaurants` contient déjà
   `result[] = [{ type: "copilotActionOutput/Search_Restaurants_<id>", value: {...} }]`
   avec la MÊME structure que celle que reçoit le renderer LWC
   (`restaurants.listRestaurants[]`, records hydratés : valeurs, displayValues,
   labels, sObjectInfo, iconUrl…). **Un client headless peut donc déjà « peindre »
   la sortie CLT sans aucune Custom Connection** — le CLT est de facto headless.
   C'est ce que fait `scripts/hxl/client.mjs` (cartes ASCII dans le terminal).

## 5. Canal retour réservation — PROUVÉ bout en bout

Constat 2026-08-30 : le sample communautaire n'implémente PAS le retour — ses boutons
HTML n'ont aucun handler ; « buttons send a chat message » (blog) n'est pas dans le code.

Design réalisé et testé : chaque carte porte un `actionText` (« Book a table at X ») ;
le client renvoie ce texte comme message → le planner route vers l'action
`Book_Restaurant` (GenAiFunction → Apex `BookRestaurantService`) → confirmation
utilisateur (`require_user_confirmation: True` → message de type **Confirm**) →
`insert as user Booking__c`. Test E2E du 2026-08-30 :

```
>>> Book a table at Blind on September 5th 2026 at 7:30 pm
agent [Confirm]: You are about to create a booking at Blind for September 5, 2026, at 7:30 PM.
>>> Yes, please confirm the booking
agent [Inform]: Your table at Blind has been booked...
SOQL: BOOKING-000000 | Blind | 2026-09-05T19:30:00.000+0000
```

L'agent est informé par construction — exactement le point de conception que la
modal LWC (toast client, `// TODO: Save booking`) ne couvrait pas.

Nuances :

- Fuseau : « 7:30 pm » a été stocké 19:30 **UTC** (parse ISO côté Apex sans TZ
  explicite). Pour de la prod : normaliser la TZ (utilisateur ou restaurant).
- `bookingDateTime` transite en `lightning__textType` ISO 8601 + parse Apex :
  `lightning__dateTimeType` fait gacker le déploiement du GenAiFunction (voir §8).

### Sélection des response formats : ne se déclenche pas (état beta)

Malgré surface + formats déployés, `plannerSurfaces` vérifié sur le planner actif,
session ouverte avec `surfaceConfig: {surfaceType: "Custom"}` (acceptée sans erreur),
et instructions renforcées (« ALWAYS use the RestaurantList response format… ») :
**aucun `SURFACE_ACTION__*` observé** en ~6 tours sur 5 sessions (ni sur le tour
liste, ni sur le tour Inquire date/heure). La doc officielle prévient : sélection
non déterministe, « no visible logs » en cas de non-sélection, fallback silencieux
en texte. Hypothèses restantes : incompatibilité avec le planner
`Atlas__ConcurrentMultiAgentOrchestration` (multi-agent Agent Script) ou avec le
template Employee Agent ; ou priorité du pipeline `copilotActionOutput`. À retester
(nouvelle version d'org, agent mono-topic, ou cas sans action displayable).
En attendant, la voie « sortie CLT hydratée » (§4) couvre la démo.

## 6. CLT/LWC vs HXL — différences constatées

- La réservation LWC actuelle est silencieuse (toast client, `// TODO: Save booking`,
  `restaurantDetails.js:92`) : l'agent n'est jamais informé. Le design headless force
  le passage par une action d'agent — structurellement mieux (record créé, agent au
  courant, confirmation native).
- Pas de date-picker vérifié : la conversation devient le formulaire
  (vs modal LWC avec champs). Le tour `Inquire` remplace la modal.
- **Câblage** : CLT/LWC = lien versionné dans le LightningTypeBundle
  (`renderer.json`) ; Custom Connections = `plannerSurfaces` dans un planner
  GÉNÉRÉ, à repatcher après chaque `sf agent publish` (script
  `scripts/hxl/wire-surface.sh`). Gros écart de maturité DX.
- **Hydratation** : le LWC ré-hydrate via LDS (`getRecords`) côté client ; l'Agent
  API livre la sortie CLT DÉJÀ hydratée (labels, displayValues, icônes) — le client
  headless n'a besoin d'aucun appel supplémentaire.
- **Multi-surface aujourd'hui** : le même agent sert le panneau Agentforce (LWC via
  CLT) ET un client headless (JSON via Agent API) sans dupliquer le schéma Apex —
  la promesse « define once » tient déjà au niveau données ; le niveau
  présentation déclarative (Mosaic/UiWidgetBundle) reste gated (pilot).

## 6bis. Setup client headless (ECA) — recette scratch org

- Les Connected Apps ne se créent PAS ici (« You can't create a connected app »
  au déploiement). Les **External Client Apps se déploient**, avec key/secret
  choisis via `ExtlClntAppGlobalOauthSettings` (non packageable, non committé).
- 4 composants : `externalClientApps/*.eca`, `extlClntAppGlobalOauthSets/*.ecaGlblOauth`
  (consumerKey/Secret, `isClientCredentialsFlowEnabled`, `isNamedUserJwtEnabled=true`
  → tokens JWT exigés par api.salesforce.com), `extlClntAppOauthSettings/*.ecaOauth`
  (scopes), `extlClntAppOauthPolicies/*.ecaOauthPlcy` (`clientCredentialsFlowUser`).
- Scopes : les tokens Agent API `chatbot_api`/`sfap_api` s'appellent **`Chatbot`**
  et **`SFApiPlatform`** dans `commaSeparatedOauthScopes` (l'erreur du validateur
  énumère la liste complète — voir §8).
- Session Agent API : `bypassUser: true` échoue (« Invalid user ID provided on start
  session: ») car l'agent Agent Script n'a pas de `default_agent_user` ;
  `bypassUser: false` (l'utilisateur du token) fonctionne pour un Employee Agent.
- Script : `scripts/hxl/setup-agent-api-app.sh` ; client : `scripts/hxl/client.mjs`.

## 7. Index des TODO(unverified) / points ouverts

- Mosaic/UiWidgetBundle : org non provisionnée (pilot) — tout le vocabulaire
  `tile/*` reste non testé serveur ; retester vers GA (Dreamforce 2026).
- Attribut « action / message chat » de `tile/button` — inconnu même dans le
  sample communautaire (boutons sans handler).
- Sélection des `AiResponseFormat` : jamais déclenchée ici (§5) — cause à isoler.
- `lightning__dateTimeType` dans un `input/schema.json` de GenAiFunction :
  fait gacker le déploiement (§8) — infirmé pour l'instant, `textType` + parse.
- Champ `invocationTarget`/`invocationTargetType` d'`AiResponseFormat` (lien
  format ↔ action invocable) : non exploré.
- Gestion de fuseau horaire de `bookingDateTime` (§5).

## 8. Log des messages d'erreur (verbatim, daté)

### 2026-08-30 — gate UiWidgetBundle

`sf project deploy start --source-dir force-app/main/default/uiWidgets --ignore-conflicts`
(org Developer scratch, API 67.0) :

```
Component Failures:
UiWidgetBundle restaurantProbe/schema           | Error | Not available for deploy for this organization
UiWidgetBundle restaurantProbe/restaurantProbe  | Error | Not available for deploy for this organization
```

Enseignement : le message n'est PAS « unknown metadata type » — le serveur reconnaît
le type et son adressage par bundle (chaque fichier du bundle est listé comme
composant `UiWidgetBundle`), mais l'org n'est pas provisionnée (pilot). C'est le
signal « feature-gated », différent d'un type inexistant.

### 2026-08-30 — câblage plannerSurfaces (Custom Connections)

Chronologie des erreurs, toutes sur `sf project deploy start` du `GenAiPlannerBundle`
récupéré :

1. Agent actif : `Cannot update record as Agent is Active` → désactiver d'abord.
2. Bundle complet (avec `agentScript/`, `agentGraph/`, `localActions/`), agent
   désactivé, avec OU sans `plannerSurfaces` :
   `An unexpected error occurred. Please include this ErrorId if you contact support:
1684973916-253159 / 1684973916-253197 / 483550139-131874 / 1684973916-253849 (-1025555067)`
   → gack systématique. Cause isolée : les dossiers `agentScript/` + `agentGraph/`
   dans le déploiement (copies générées, en conflit avec l'AiAuthoringBundle).
3. XML seul (sans aucun sous-dossier) : **Succeeded… mais DESTRUCTIF** — les schémas
   input/output du localAction sont effacés côté org. Symptôme différé : tout
   retrieve du type échoue ensuite avec
   `RESOURCE_NOT_FOUND: We couldn't retrieve the action "c__Search_Restaurants_<id>"
because an input or output schema is missing.` Récupération : redéployer le
   bundle complet original (passe alors, les enfants manquants suivent la voie
   « create ») ou republier l'authoring bundle.
4. **Forme qui marche** : XML + `localActions/` (sans `agentScript/`/`agentGraph/`) →
   erreurs de validation propres puis Succeeded.
5. `Surface does not exist in org: RestaurantChat_RestoHXL1` alors que le déploiement
   AiSurface/AiResponseFormat précédent avait répondu Succeeded (composants absents de
   `sf org list metadata` et d'un retrieve juste après). Re-déployer les MÊMES fichiers
   → `created: true` avec des IDs réels, et cette fois ils persistent. Non élucidé
   (rollback silencieux du premier deploy ?) — si « Surface does not exist » apparaît,
   redéployer les surfaces et réessayer.
6. `sf agent activate` sans `--version` devient interactif dès qu'il existe 2 versions
   de bot (le republish en crée une) → toujours passer `--api-name` + `--version`.

### 2026-08-30 — GenAiFunction Book_Restaurant

- `lightning__dateTimeType` dans `input/schema.json` →
  `An unexpected error occurred. Please include this ErrorId if you contact support:
483550139-132460 (59220073)`. Avec `lightning__textType` (ISO 8601 + parse Apex),
  le déploiement passe.
- Déploiement du GenAiFunction avant la classe Apex (rollback de transaction) →
  `InvocableTarget not found: BookRestaurantService` : déployer les classes d'abord.

### 2026-08-30 — External Client App / Agent API

- Connected App : `You can't create a connected app. To enable connected app
creation, contact Salesforce Customer Support.` → passer par les ECA.
- Scopes ECA invalides → le validateur énumère la liste complète :
  `[Basic, OfflineAccess, DataCloudUserClaims, Email, Address, CDPSegment, Chatbot,
CustomApplications, Full, Profile, CDP, CDPProfile, RefreshToken, Phone,
PwdlessLogin, Interaction, Pardot, CDPIngest, CDPIdentityResolution,
CustomPermissions, ForgotPassword, UserRegistration, OpenID, Chatter, Wave,
SFApiPlatform, SCRT, Web, EinsteinGPT, Lightning, Content, CDPCalculatedInsight,
Eclair, Api, MCP, CDPQuery]` → `chatbot_api` = `Chatbot`, `sfap_api` = `SFApiPlatform`.
- Agent API `POST /sessions` avec `bypassUser: true` →
  `Bad Request: Invalid user ID provided on start session:` (agent sans
  `default_agent_user`) → `bypassUser: false`.

## 9. Matrice de livraison HXL — extraite du playground (2026-08-31)

Le bundle JS du playground (`headlessexperiencelayer.com/playground/assets/main-*.js`,
4,7 Mo) embarque la liste des hôtes cibles et de leur protocole de livraison, avec
un statut. Extrait verbatim (structure `{id, name, protocols:[{id, name, support}]}`) :

| Hôte                  | Protocole                      | Statut                      |
| --------------------- | ------------------------------ | --------------------------- |
| Claude                | MCP Apps (`claude-mcp`)        | `devPreview`, since 262.16  |
| ChatGPT               | MCP Apps (`chatgpt-mcp`)       | `devPreview`, since 262.4   |
| Slackbot              | MCP Apps (`slack-mcp`)         | `devPreview`, since 262.4   |
| Slack                 | Block Kit (`slack-blockkit`)   | `planned`, target 262.12+   |
| MS Teams              | Adaptive Cards (`teams-ac`)    | `inProgress`, target 262.12 |
| Gemini                | A2A (`gemini-a2a`)             | `planned`, target 262.12+   |
| Agentforce Mobile SDK | Native / MCF (`mobile-native`) | `planned`, target 262.16+   |

Menu « renderer » du playground : `acc` (Agentforce natif), `mcp-app` + `theme`
∈ {`slack`, `chatgpt`, `claude`}, `adaptive-cards` (Teams). Donc « Claude » =
MCP App + jetons CSS de Claude (cf. `var(--color-text-primary, …)` dans le widget
du repo communautaire) — un seul mécanisme de livraison, trois thèmes.

Constats :

- Zéro occurrence de `a2ui` dans le bundle ; la voie Google est « A2A », plus tard.
- Les hôtes tiers via MCP Apps sont en _dev preview_ (262.x = ligne Summer '26,
  notre org est API 67 = 262) — cohérent avec le gate « Not available for deploy
  for this organization » sur `UiWidgetBundle`.
- Ce sont des chaînes dans du JS livré, pas des engagements : à citer comme signal.

## 10. Documentation officielle HXL trouvée (2026-09-01) — tout change

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

### Câblage à une action Agentforce (répond à l'inconnue §3)

`renderer.json` à la **racine** du LightningTypeBundle (pas dans un dossier canal) :
`"componentOverrides": { "$": { "definition": "@widget/c/<widget>", "attributes": { "<attrWidget>": "{!$attrs.<propCLT>}" } } }`.
Déployer le widget avant le CLT (ou ensemble). Puis Setup → Agentforce Assets → Actions →
sortie structurée → « Show in conversation » + « Output Rendering » = le CLT.
LWC override = dossier canal ; widget HXL = racine, multi-surface.

### Canal retour (répond à l'inconnue §5)

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

### 10.1 Gate, second essai (2026-09-01) — après `hxlEnabled=true`

Deploy `settings/UiWidget.settings-meta.xml` (`hxlEnabled=true`) : OK (`Changed Settings UiWidget`).
Deploy `uiWidgets/restaurantProbe` : **échec différent** →
`UiWidgetBundle restaurantProbe | Workspace 'DefaultWidgetSpace' not found`.
Lecture : le type est désormais accepté par le validateur (gate « disponibilité » franchi) ; il
manque un « workspace » par défaut, vraisemblablement provisionné par le toggle Setup UI
(« Headless Experience Layer Settings ») plutôt que par le seul deploy du settings.
Sondages sans résultat : retry après 20 s (même erreur) ; aucun type de métadonnées ni sObject
« _Space_ » lié ; Tooling `EntityDefinition LIKE '%Widget%'` → seule `UiWidgetLocalization`.
Hypothèse : `DefaultWidgetSpace` est provisionné par le toggle Setup UI (« Headless Experience
Layer Settings »), pas par le deploy du settings. À vérifier en basculant le toggle dans l'UI.

### 10.2 Enquête « DefaultWidgetSpace » (2026-08-31)

Toggle Setup UI « Headless Experience Layer (Beta) » basculé off/on par l'utilisateur : même erreur.
Sondages (tous négatifs) :

- deploy en `--api-version 68.0` : même erreur ; `UiWidgetBundle` listé mais aucun widget dans l'org ;
- permissions utilisateur `*Widget*`/`*Hxl*` : aucune (seules `HeadlessCMSAccess`, `HeadlessPublishNudges`) ;
- glossaire, page Vibes, page configuration du bundle : aucune mention de workspace ;
- hypothèse CMS (la racine du widget s'appelle `contentBody`) : `/connect/cms/spaces` = `[]` →
  création d'un espace CMS `DefaultWidgetSpace` (apiName `DefaultWidgetSpace`, fqn `DefaultWidgetSpace--content`) :
  même erreur. (Espace non supprimable par API — HTTP 405 — à supprimer dans l'app Digital Experiences.)
- hypothèse Files (`ContentWorkspace` = bibliothèques) : création d'une bibliothèque `DefaultWidgetSpace` : même erreur (supprimée ensuite).
  Conclusion provisoire : le « workspace » est un objet interne non exposé, censé être provisionné par
  l'activation (job async ?) et absent de ce scratch org. Pistes : scratch org créé avec
  `uiWidgetSettings.hxlEnabled=true` dès la définition ; ou org Developer Edition non-scratch.
- hypothèse `UnstructuredStorageSpace` (entité créable : `SpaceName`, `ApplicationName`, `FolderId`=Org) :
  création `SpaceName=DefaultWidgetSpace, ApplicationName=UiWidget` → Salesforce provisionne un vrai
  stockage (`StorageLocation: defaultwidgetspace_kat9`, `SpaceType: Public`) — mécanisme réel — mais le
  deploy échoue toujours : l'`ApplicationName` attendu est inconnu (picklists internes vides). Record supprimé.
  Arrêt des sondages à l'aveugle. Reste dans l'org : l'espace CMS `DefaultWidgetSpace` (non supprimable par API).

### 10.3 Scratch org neuf avec `uiWidgetSettings.hxlEnabled=true` (2026-08-31)

Définition dédiée : `config/project-scratch-def-hxl.json` (copie de la def standard + `"uiWidgetSettings": {"hxlEnabled": true}`).
Org `lwc-in-agentforce-hxl-probe` créée (Developer Edition, expire 2026-09-07). Résultat :

- `/connect/cms/spaces` = `[]`, `UnstructuredStorageSpace` = `[]`, bibliothèques = Asset Library seule ;
- deploy du probe : **`Workspace 'DefaultWidgetSpace' not found`** — identique.
  Conclusion : en scratch org, activer HXL (settings ou toggle UI) ne provisionne pas le workspace requis.
  Reste à tester une org Developer Edition non-scratch (provisioning possiblement lié au signup d'org).

### 10.4 État du gate (2026-08-31, fin de session)

Test en org Developer Edition non-scratch : **non réalisé** (décision : ne pas activer la beta dans les orgs DE existantes).
Bilan : HXL est documenté et le type `UiWidgetBundle` est reconnu, mais aucun scratch org (toggle a posteriori
ou `hxlEnabled` à la création) ne provisionne le workspace `DefaultWidgetSpace` requis au deploy.
Le gate reste fermé côté widget ; la partie agent (Book_Restaurant) et l'enveloppe MCP restent livrables.
Org de sondage `lwc-in-agentforce-hxl-probe` conservée (expire 2026-09-07) — à supprimer si inutile.

## 11. CLT « rôles MCP » déployés (2026-08-31)

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
  → La résolution `@widget/<ns>/<nom>` fonctionne ; seule l'absence du widget (gate workspace) bloque.
  En attendant, `uiWidgets/**` et ce `renderer.json` sont exclus via `.forceignore` pour que le
  déploiement complet de `force-app/` (script de démo) reste vert — les fichiers restent en repo.

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

## 12. Référence composants consolidée (lecture intégrale via .md, 2026-08-31)

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

## 13. Traçabilité des sources produit (2026-08-31)

L'article de release notes produit `rn_headless360` (release 262) est inaccessible à tout outillage :
SPA help.salesforce.com (page d'erreur hors navigateur), non indexé par Google (seule sa meta-description
remonte : « Headless 360 features and changes are released as often as monthly »), absent de l'index MCP
docs (qui s'arrête à la release 260), PDF resources.docs 404. Seul un navigateur humain y accède.
Note : la phrase « the host caches the widget aggressively » (Apex Hours, 24/08/2026) concerne le cache
du widget MCP Apps côté Claude Desktop dans LEUR démo (workaround : ⌘Q + nouveau chat après un
handshake raté) — pas une limitation officielle de la plateforme.
Vérification exhaustive « widget space » côté Metadata API (2026-08-31) :

- pas de page meta_uiwidgetspace ni meta_uiwidgetsettings (redirections vers l'accueil du guide) ;
- la page « Settings » du guide (~150 types) ne liste PAS UiWidgetSettings — pourtant retrieve/deploy OK ;
- Metadata Coverage Report (873 types, v67 & v68) : zéro entrée _widget_/_hxl_ — même UiWidgetBundle absent ;
- guide HXL (47 pages) : aucune occurrence de workspace côté déploiement.
  Conclusion : `DefaultWidgetSpace` est une entité interne citée uniquement par l'erreur de deploy —
  aucun canal public ne la documente. Trois couches de retard doc : type documenté hors coverage report,
  settings non documenté, workspace inexistant partout.

### 10.5 Scratch org en release preview (Winter '27, API 68.0) — 2026-08-31

Définition `config/project-scratch-def-hxl-preview.json` (= def HXL + `"release": "preview"`).
Org `lwc-in-agentforce-hxl-preview` créée (API max confirmée : **68.0 « Latest Release »**, expire 2026-09-07).
Constat identique : `/connect/cms/spaces` = `[]`, `UnstructuredStorageSpace` = `[]`, et le deploy du probe →
**`Workspace 'DefaultWidgetSpace' not found`** — à l'octet près la même erreur qu'en 262/API 67.
Conclusion : le défaut de provisioning n'est pas corrigé dans la preview Winter '27 ; il ne dépend ni de la
release ni du moment de l'activation. Le provisioning du workspace semble réservé à un flux de signup
d'org non-scratch (ou pas encore livré du tout côté deploy public).
Gotcha outillage : nos exclusions `.forceignore` (uiWidgets/\*\*) s'appliquent aussi aux deploys de sondage —
premier essai parti en `NothingToDeploy` ; contourné en écartant temporairement le fichier.
Orgs de sondage actives : `lwc-in-agentforce-hxl-probe` et `lwc-in-agentforce-hxl-preview` (expirent le 07/09).

## 14. Second repo communautaire : hxl-mcp-widget-sample (2026-09-10)

Source : https://github.com/hinabasfdc/hxl-mcp-widget-sample (Hiroyuki Inaba, Salesforce Japon,
28/08/2026), sources d'un billet du blog développeur japonais
(`developer.salesforce.com/jpblogs/2026/08/headless-experience-layer-custom-ui-widget-jp`, 403 hors navigateur).
Cas : carte « résumé des opportunités d'un compte » affichée dans ChatGPT / Claude via MCP.

Structure strictement identique à la nôtre (§11) : Apex `@InvocableMethod` → `GenAiFunction` → trois
LightningTypeBundles (wrapper Apex, `OutputValues`, `Result` taggés `mcp`) → `renderer.json` racine
`@widget/c/accountSummaryCard` → `UiWidgetBundle` (`widgetType` JSON) → `McpServerDefinition` avec
`<resources>`/`<uiResource>`. Rien de nouveau côté vocabulaire Mosaic.

Apports réels :

- **Prérequis org (README)** : instance « Summer '26 Patch 14.4 ou ultérieur », HXL activé, et
  « Developer Edition ou Sandbox recommandé pour la vérification ». Aucune mention de scratch org.
  Un troisième témoignage indépendant que ça fonctionne en org DE/sandbox.
- **Vérification patch** : nos scratch orgs (`lwcinagentforce`, `hxl`) sont sur **Winter '27 Patch 4.7**
  (Trust API `api.status.salesforce.com/v1/instances/<InstanceName>/status`), donc au-delà du prérequis.
  Dry-run du widget du repo sur les deux orgs : **`Workspace 'DefaultWidgetSpace' not found`**, identique.
  Le niveau de patch n'est pas la cause ; le constat §10.4 (scratch org ne provisionne pas le workspace) tient.
- **Pattern « pré-formatage en Apex »** : le widget ne consomme que des `lightning__textType`
  (`accountInitials`, `totalOpportunityCountText`, `openOpportunityAmountFormatted`, `stageSummaryText`
  concaténé). Pas de `forEach`, pas de `table` : toute la mise en forme est faite côté Apex.
  À garder en tête si l'itération Mosaic se révèle limitée sur une surface.
- **Gotcha cache MCP Apps** : le hôte cache le template par `resourceUri`. Si une modif du widget
  n'apparaît pas : « Refresh tools » côté client ; sinon dupliquer le LightningTypeBundle sous un nouveau
  nom d'API (`…ResultV2`), mettre à jour `<resourceUri>`/`<uiResource>` et ré-enregistrer le connecteur.
  Confirme (côté plateforme cette fois) la remarque Apex Hours du §13.
- Le `GenAiFunction` y sert uniquement d'enregistrement dans l'API Catalog pour le tool MCP ; aucun
  câblage à un agent Agentforce n'est montré.

### 14.1 L'article lui-même (lu via proxy r.jina.ai, publié le 24/08/2026)

Le site renvoie 403 à tout client non-navigateur ; `r.jina.ai/<url>` passe. Ce qu'il ajoute au README :

- **Beta « fin août 2026 »** (« 2026年8月後半よりベータ公開 »). Cohérent avec notre §10 (doc apparue le 01/09).
- **Le patch conditionne l'apparition du toggle**, pas le deploy : « si ce réglage n'apparaît pas, vérifier
  que l'instance est en Summer '26 Patch 14.4 ou ultérieur ». Chez nous le toggle existe et le deploy
  échoue plus loin : le patch n'est donc pas notre problème (cf. dry-run ci-dessus, Winter '27 Patch 4.7).
- **Scratch org** : citée une fois, dans une mise en garde générique (« Sandbox / Developer Edition / Scratch
  Org plutôt que production »), mais « la procédure a été vérifiée en Developer Edition ». Aucune mention de
  workspace ni de `DefaultWidgetSpace`. L'auteur n'a manifestement pas testé en scratch org.
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

## 15. Le gate s'ouvre : org non-scratch (2026-09-10)

Org `new-prerelease` créée par l'utilisateur (signup pre-release, `texe3.my.salesforce.com`) :
instance USA794, **Winter '27 Patch 4.7** (même patch que les scratch orgs), Enterprise Edition,
`IsSandbox=false`. Toggle HXL activé dans Setup, puis deploy du `restaurantProbe` : **succès**.
Conclusion définitive de l'enquête §10 : le workspace `DefaultWidgetSpace` est provisionné par le
signup d'une org « normale », jamais par un scratch org (quel que soit le patch, la release ou le
moment de l'activation). Le hook deploy-gate du plugin classe cette org en « production »
(EE non-sandbox) ; contourné avec `CONFIRM_PROD=1`, l'org étant dédiée au test.

### 15.1 Syntaxe d'itération, enfin sourcée

La page `guide/hxl-widget-composition.html` (lue en texte brut via `r.jina.ai`, les blocs JSON
sont perdus mais la prose est complète) documente l'objet `meta` : `if` (booléen strict, null = false),
`forEach` (collection), `forItem` (doit commencer par `$`, défaut `$Item`), `forIndex`. `if` + `forEach`
combinés = filtre par item ; `if` sur `$attrs.x` dans un `forEach` = évalué une fois pour toute la liste.
Formules : moteur Salesforce (`{!$order.subtotal * $order.taxRate}`), exemples dans le Playground `#06-formulas`.
Zips d'exemple officiels (hotelCard widget, hotelInfo CLTs, Apex) téléchargeables depuis
`resources.docs.salesforce.com/rel1/doc/en-us/static/misc/{HotelCardWidget1,HotelInfoLightningTypes1,HotelSearchResultApexClassBundle1}.zip`
— notre `uiWidgets/hotelCard` est identique à l'octet près. Aucun exemple officiel d'attribut collection.

### 15.2 Widget `restaurantList` (étape 3 du plan) — déployé

`uiWidgets/restaurantList/` : `forEach` sur `{!$attrs.restaurants}` (`forItem: "$restaurant"`), un
`tile/container` par restaurant : nom (h3) + badge `PriceRange__c`, icône `star` + `NumberOfStars__c`,
cuisine, et un `tile/button` « Book a table » → `action/sendMessage` (cf. §15.4).

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

### 15.3 CLT « Agentforce » séparé : `restaurantHxlResponse`

Pour rester additif (l'agent continue d'utiliser `c__restaurantResponse` → LWC), nouveau CLT
`lightningTypes/restaurantHxlResponse/` : même `@apexClassType/c__RestaurantService$Restaurants`,
`renderer.json` **à la racine** → `@widget/c/restaurantList` avec `restaurants: "{!$attrs.listRestaurants}"`.
Basculer l'agent = Setup → Agentforce Assets → Actions → Search Restaurants → sortie `restaurants` →
Output Rendering = `Restaurant HXL Response` (ou `complex_data_type_name: "c__restaurantHxlResponse"`
dans le `.agent`). Les quatre CLT (LWC, HXL, payload MCP, wrapper MCP) déploient ensemble sans erreur :
la validation design-time du mapping renderer → attributs du widget passe, y compris vers un attribut liste.

### 15.4 Canal retour (étape 4) — choix de conception

`content` du `sendMessage` : `"Book a table at {!$restaurant.Name} (restaurant Id {!$restaurant.Id})"`.
Le texte revient au subagent `Restaurant_Management`, dont les instructions demandent date/heure puis
appellent `Book_Restaurant` ; l'entrée `restaurantId` (`isUserInput: false`) peut être extraite du message
par le planner. TODO(unverified) : interpolation d'un token au milieu d'un littéral (accepté au deploy,
à vérifier au rendu) ; alternative formule `{!"Book a table at " & $restaurant.Name}`.

### 15.5 État de l'org `new-prerelease` après deploy complet de `force-app/`

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

### 15.6 `McpServerDefinition` : déployable sans Einstein

`mcpServerDefinitions/restaurantsearchserver.mcpServerDefinition-meta.xml` (calqué sur le repo hinaba,
§14) : tool `aa:apex-RestaurantService` (`apiSource: API_CATALOG`, `toolName:
RestaurantServiceapex_RestaurantService`), `uiResource: restaurantList` → resource
`ui://widget/lightningType/c__restaurantSearchMcpResult`. **Deploy OK** alors que les `GenAiFunction`
sont refusés : l'API Catalog référence directement la classe `@InvocableMethod`, le `GenAiFunction`
n'est pas un prérequis (contrairement à ce que suggère le README hinaba). Reste côté Setup :
API Catalog → MCP Servers → Activate, External Client App (PKCE, JWT, scope MCP), puis connecteur
Claude Desktop / ChatGPT sur `https://api.salesforce.com/platform/mcp/v1/custom/restaurantsearchserver`
(cf. §10). Non testé : ce chemin permettrait de voir le widget rendu **sans Agentforce**.

Hors HXL, spécifique org non-scratch : les champs custom déployés n'ont pas de FLS pour l'admin
(en scratch org, le deploy l'accorde au profil). L'import `sf texei data import` échoue en
`INVALID_FIELD NumberOfStars__c` tant que le permset `Restaurants_Management` n'est pas assigné —
lequel ne se déploie pas (`agentAccesses` → Bot inexistant). Contournement : version du permset sans
`agentAccesses` déployée depuis un projet temporaire, assignée, puis import (`Data imported`).
Le permset complet (avec `tabSettings`/`applicationVisibilities`) exige que tabs et app soient déjà
dans l'org — déployés ensuite par lot (tabs, applications, layouts, thème, `post-push-source/settings`).

### 15.7 Reste à faire (nécessite une action Setup côté utilisateur)

1. Activer Einstein / Agentforce dans l'org `new-prerelease` (Setup → Einstein Setup), si l'org y a droit.
2. Rejouer `sf project deploy start --source-dir force-app` (les 5 composants AI), puis
   `sf agent publish authoring-bundle --api-name Restaurant_Agent --skip-retrieve`, puis
   `sf project deploy start --source-dir post-push-source` (permset complet avec `agentAccesses`).
3. Setup → Agentforce Assets → Actions → Search Restaurants → sortie `restaurants` →
   Output Rendering = **Restaurant HXL Response** → tester « restaurants in Paris » dans le Builder ;
   cliquer « Book a table » et vérifier que le subagent enchaîne sur `Book_Restaurant` (canal retour, §15.4).
4. Voie MCP sans Agentforce : Setup → API Catalog → MCP Servers → `restaurant-search-server` → Activate ;
   External Client App ; connecteur Claude Desktop → le même widget doit s'afficher dans Claude.

## 16. Contre-enquête « DefaultWidgetSpace » : dev org vs scratch, seconde passe (2026-09-10)

Seconde comparaison, indépendante de celle de `docs/hxl-comparison-2026-09-10/` (qui n'avait rien trouvé
côté settings, licences, CMS). Scratch org neuve `hxl-compare-claude` (`00DhP000000cUyPUAU`, Developer,
release preview, instance USA1154S, expire 2026-09-17) créée depuis `config/project-scratch-def-hxl-preview.json`
sans modification. Deploy du `restaurantProbe` : **`Workspace 'DefaultWidgetSpace' not found`**
(deploy `0AfhP000000kT3pSAE`). Reproduit, donc.

### 16.1 Ce qui est identique (et donc hors de cause)

- `UiWidgetBundle` présent dans `describeMetadata` des deux orgs ; `hxlEnabled=true` des deux côtés
  (audit trail : `hxlEnabledOffOn` à 12:06:48 sur la dev org via le toggle Setup, à 14:08:13 sur la scratch
  via la définition).
- Entités « espace » exposées par Tooling et REST : exactement la même liste sur les deux orgs
  (`ContentWorkspace*`, `ManagedContentSpace`, `SchedulingWorkspace*`, `UnstructuredStorageSpace*`,
  `UiWidgetLocalization`, `IDEWorkspace`). Aucune entité au préfixe `1id` (celui des IDs de `UiWidgetBundle`
  côté dev, ex. `1idWs0000000oWHIAY`) n'est exposée nulle part : le stockage du widget est interne.
- Sur la dev org qui **marche** : `/connect/cms/spaces` = `[]`, `UnstructuredStorageSpace` = 0 ligne,
  une seule `ContentWorkspace` (Asset Library). `DefaultWidgetSpace` n'est donc ni un espace CMS, ni une
  bibliothèque Files, ni un `UnstructuredStorageSpace` — même sur l'org fonctionnelle. Inutile d'en créer un.
- Objets Tooling MCP identiques (`McpServerDefinition`, `McpServerResourceDefinition`, …) ; permsets C2C
  identiques, dont `C2CMcpServicePermSet` (lecture de `McpServerDefinition` + `PermissionsApiEnabled`),
  présent et non assigné sur la scratch.
- Ressources REST racine identiques à deux exceptions près (`ai`, `match` en plus sur la scratch — Einstein).
- Aucun package installé lié à HXL sur la dev org (seulement CRM Dashboards et Salesforce Mobile Apps).
- `TenantUsageEntitlement` : aucun entitlement HXL/widget/MCP d'un côté ni de l'autre.
- Endpoints devinés (`/connect/widgets`, `/connect/hxl`, `/ui-widgets`, `/connect/cms/workspaces`,
  `/connect/unstructured-storage/spaces`) : `NOT_FOUND` sur les deux orgs.

### 16.2 Les deux vraies différences observées

1. **Les scratch orgs sortent d'un pool pré-provisionné.** `Organization.CreatedDate` de `hxl-compare-claude`
   = 2026-09-08 18:48 UTC, deux jours *avant* ma commande `sf org create scratch` (14:08 UTC le 10). L'audit
   trail le confirme : signup générique le 8 (`value_ORG_CREATED_ON_VERSION 264.0`, `SCRT2 Integration User`,
   flexipages par défaut), puis application de la définition le 10 (`hxlEnabledOffOn`, `agentPlatformEnabledOffOn`,
   permsets Agentforce). Idem pour toutes les autres scratch orgs (`hxl-preview-compare-20260910` créée le 8,
   `hxl-preview-enterprise-20260910` le 29/08, `hxl` et `lwcinagentforce` le 01/09). La dev org
   `new-prerelease`, elle, est un signup réel à 11:56 UTC le 10. Toute étape de provisioning exécutée
   **au signup** (et non au moment où on active un setting) manque donc aux scratch orgs si elle n'était
   pas dans le template du pool.
2. **Sur la dev org, le premier deploy de widget déclenche un provisioning automatique.** Audit trail :
   `Automated Process` assigne `C2CMcpServicePermSet` au `Platform Integration User` à **12:15:21**, et
   le widget `restaurantProbe` est créé à **12:15:28** (`sf org list metadata`). Rien d'équivalent sur la
   scratch : après mes deux deploys en échec, l'audit trail ne contient que mes propres actions de test.
   Le deploy d'un `UiWidgetBundle` passe donc par un service cloud-to-cloud (« C2C », préfixe des permsets
   d'intégration plateforme) — vraisemblablement le service MCP/widget qui héberge le « workspace ».
   Contre-test : assigner `C2CMcpServicePermSet` à la main au Platform Integration User de la scratch puis
   redéployer → **même erreur** (deploy `0AfhP000000kTDVSA2`) ; assignation supprimée ensuite.
   L'assignation est une *conséquence* du provisioning réussi, pas sa cause.

Lecture : le « workspace » est créé côté service C2C au premier appel réussi, et cet appel échoue depuis
les scratch orgs. Les scratch orgs vivent sur des instances sandbox (`USA1154S`, `USA1130S`, `USA32S`,
`USA946S`, `USA1202S` — suffixe S, `IsSandbox=true`) alors que la dev org est sur `USA794` (pod de
production, `IsSandbox=false`). Hypothèse la plus économe : le service C2C des widgets n'est pas câblé
(ou pas autorisé) pour les pods sandbox/scratch en beta. Non prouvable depuis l'org : le service et le
workspace ne sont exposés par aucune API.

### 16.3 Le test qui trancherait : scratch org depuis la shape de `new-prerelease`

Si une scratch org créée avec `sourceOrg = 00DWs00000TDFi5` (mêmes features, settings, licences que l'org
qui marche) échoue aussi, plus aucune différence de configuration n'est en cause — seule l'infrastructure
scratch/sandbox reste. Préparation faite :

- `DevHubSettings.enableShapeExportPref` passé à `true` sur `new-prerelease` (deploy `0AfWs00001cBZQgKAO` ;
  valeur d'origine `false`, à remettre une fois le test fini) ;
- `sf org create shape --target-org new-prerelease` → shape `3SRWs00000CqDjpOAF` ;
- `sf org create scratch` avec `sourceOrg` → **`RemoteOrgSignupFailed` : « Contact the source org admin to
  add your Dev Hub org ID to Setup > Org Shape »**. Il faut saisir l'ID 15 caractères du Dev Hub `texei`
  (`00D46000000ZOHT`) dans `new-prerelease` → Setup → **Scratch Orgs** (nouveau nom de la page ; toggle
  « Enable Org Shape for Scratch Orgs » + champ Dev Hub org ID). Pas d'API pour l'ID.
  `enableShapeExportPref` n'est pas déprécié (doc Metadata API : disponible API 55.0+, sans avertissement).
  Définition prête dans le scratchpad de session (`sourceOrg`, `release: preview`, `hxlEnabled`).

Pas de test sandbox possible : `/limits` de `new-prerelease` n'annonce aucune licence sandbox (org trial).

### 16.4 Résolu : le facteur décisif est le Dev Hub (2026-09-10)

L'utilisateur a activé Dev Hub sur `new-prerelease` (irréversible, son choix). Scratch org créée depuis ce
Dev Hub avec la **même définition** (`config/project-scratch-def-hxl-preview.json` sans le champ
`release` : depuis un hub déjà en pre-release, `"release": "preview"` renvoie `VR-0003`
« Check that the release value is valid ») :

- `hxl-from-prerelease-hub`, `00Dh9000000NafVEAS`, Developer, instance **USA1208S** (pod sandbox,
  `IsSandbox=true`), API 68.0, `hxlEnabled` appliqué par la définition (`hxlEnabledOffOn` 14:39:02) ;
- `Organization.CreatedDate` = **14:35:42**, soit l'heure de la commande : signup frais, pas une org de pool
  (l'audit trail démarre à 14:36:40 avec la séquence de signup complète) ;
- deploy `restaurantProbe` : **Succeeded** (`0Afh900000097wkCAA`, widget `1idh900000002UrAAI`) ;
- deploy complet de `force-app` : **48 composants, 0 erreur** (`0Afh900000098kjCAA`) — CLT, widgets,
  Apex, `GenAiFunction`, `AiAuthoringBundle`, `McpServerDefinition` ;
- suite de la chaîne du README, sans accroc : `sf agent publish authoring-bundle` (3 déployés),
  `post-push-source` (`0Afh900000098pZCAQ`), permset `Restaurants_Management` assigné, `sf texei data import`
  → « Data imported ». L'org est prête pour le test de rendu Agentforce (§15.7 étape 3), enfin en scratch org.

Piège CLI au passage : l'auth de `new-prerelease` datait d'avant l'activation Dev Hub, le CLI avait mis en
cache `isDevHub=false` → `NotADevHubError`. Corrigé en patchant `~/.sfdx/<username>.json` (`isDevHub: true`)
après avoir vérifié que `ScratchOrgInfo` est interrogeable ; un `sf org login web` refait le même travail.

Ce que ça corrige dans §16.2 : l'auto-assignation de `C2CMcpServicePermSet` sur la dev org **n'est pas**
liée au deploy de widget — sur cette scratch, le widget se déploie sans qu'elle apparaisse dans l'audit trail.
Coïncidence horaire, piste abandonnée. Et le pod sandbox n'est pas la cause non plus (USA1208S marche).

Reste donc une seule variable : **le Dev Hub**. Deux lectures compatibles avec tout ce qui a été observé :

1. **Pool vs signup frais.** Les scratch orgs de `texei` (Dev Hub ancien, API 65 côté hub) sortent d'un pool
   d'orgs pré-créées (CreatedDate J-2 à J-12), dont le template ne contient pas le workspace HXL ; celles
   du hub pre-release sont créées à la demande, par un signup complet qui le provisionne.
2. **Entitlement hérité du Dev Hub.** Le workspace serait provisionné selon les features/licences du hub
   (org pre-release EE, Winter '27 signup récent) — « certains trucs redescendent ».

### 16.5 Deux tests de plus, et la vraie variable : le temps après le toggle (2026-09-10)

Test A — signup frais depuis `texei` : même définition + `"country": "FR", "language": "fr"` (combinaison
absente du pool US/en_US) → `hxl-texei-fr`, `00DO800000YLc6pMAD`, USA268S, `Organization.CreatedDate`
= 14:56:38, heure de la commande : **signup frais**. Deploy du probe 32 s après le toggle : **échec**.

Test B — deuxième org depuis `new-prerelease` → `hxl-from-prerelease-hub-2`, `00Ddh00000ChxQvEAJ`,
**USA932S** (autre instance que la première). Deploy 28 s après le toggle : **échec**. Donc ni le Dev Hub
ni l'instance n'expliquent le succès de la première org.

Puis, quelques minutes plus tard, **redeploy sur les trois orgs en échec** :

| Org | Origine | `hxlEnabledOffOn` | 1er deploy | 2e deploy |
| --- | --- | --- | --- | --- |
| `hxl-from-prerelease-hub` | signup frais, hub pre-release | 14:39:02 | 14:43:35 **OK** (+4 min 33) | — |
| `hxl-from-prerelease-hub-2` | signup frais, hub pre-release | 15:08:27 | 15:08:55 KO (+28 s) | 15:10:32 **OK** (+2 min 05) |
| `hxl-texei-fr` | signup frais, hub `texei` | 14:59:26 | 14:59:58 KO (+32 s) | 15:10:47 **OK** (+11 min) |
| `hxl-compare-claude` | **pool** (créée le 08/09), hub `texei` | 14:08:13 | 14:09:08 KO | 14:14:17 KO, 15:11:01 **KO** (+63 min) |

(Horodatages : `DeployRequest` via Tooling, `SetupAuditTrail` pour le toggle. Patch : les 8 instances
sandbox impliquées et USA794 sont toutes en **Winter '27 Patch 4.7 / 264.4.7** d'après l'API Trust.)

Lecture : `hxlEnabled=true` déclenche un **provisioning asynchrone** du workspace `DefaultWidgetSpace`,
prêt en ~2 minutes sur une org de signup frais. Toutes les tentatives « toggle puis deploy immédiat »
de §10 à §16.4 étaient trop tôt. Le seul cas qui résiste est l'org de **pool** (`hxl-compare-claude`),
toujours en échec une heure après — comme les orgs `hxl`, `lwcinagentforce` et celles de la première
passe, toutes issues du pool, où personne n'a jamais attendu 10 minutes après un toggle. Test en cours :
cycle off/on par Metadata API sur `hxl-compare-claude`, puis redeploy après 10 minutes (§16.6).

Ce que ça retire : l'entitlement du Dev Hub, l'instance, le patch, la locale, l'org shape. Les
comparaisons de settings/licences (`docs/hxl-comparison-2026-09-10/`) étaient hors sujet dès le départ.

### 16.6 L'org de pool ne rattrape pas, même avec un cycle et 10 minutes (2026-09-10)

Sur `hxl-compare-claude` : `hxlEnabled=false` (`0AfhP000000kURKSA2`) puis `true` (`0AfhP000000kUuLSAU`)
à 15:13, attente de 10 minutes, redeploy à 15:23 → **`Workspace 'DefaultWidgetSpace' not found`**
(`0AfhP000000kUfqSAE`). Le job asynchrone qui provisionne le workspace ne se déclenche donc pas sur
une org de pool, quel que soit le nombre de toggles ni le délai.

**Bilan de l'enquête §10 → §16, en trois lignes :**

1. `hxlEnabled=true` lance un provisioning asynchrone (~2 min) du workspace `DefaultWidgetSpace`, sans
   trace dans aucune API de l'org. Déployer un `UiWidgetBundle` avant, c'est l'erreur du titre.
2. Ce provisioning ne fonctionne que sur une org issue d'un **signup réel** au moment de la demande.
   Les scratch orgs servies depuis le **pool pré-provisionné** de l'instance (`Organization.CreatedDate`
   antérieure de plusieurs jours à `sf org create scratch`) ne l'obtiennent jamais.
3. On ne choisit pas le pool. Ce qui a forcé un signup frais dans nos tests : un Dev Hub tout neuf
   (`new-prerelease`, 2/2) ou une combinaison pays/langue absente du pool (`country: FR, language: fr`
   depuis `texei`, 1/1). Toutes les orgs US/en_US de `texei` (6/6) venaient du pool.

Recette scratch org HXL qui marche aujourd'hui : `config/project-scratch-def.json` (def d'origine +
`"country": "FR", "language": "fr"` + `uiWidgetSettings.hxlEnabled`, intégrés le 10/09), vérifier
`SELECT CreatedDate FROM Organization` ≈ heure de création, attendre 2 à 3 minutes après la fin de
`sf org create scratch`, puis déployer. Si `CreatedDate` est vieille de plusieurs jours : org de pool,
la supprimer et recommencer. `release: preview` gardé : il ne joue pas sur le pool, mais depuis un hub
déjà en pre-release il faut l'enlever (VR-0003, §16.4).
Orgs fonctionnelles au 10/09 (expirent le 17/09) : `hxl-from-prerelease-hub` (démo complète déployée,
§16.4), `hxl-from-prerelease-hub-2`, `hxl-texei-fr`.

Langue et pool, précisions (16:00) : le pool est indexé par la **langue**, pas le pays. `country: FR` +
`language: en_US` → org de pool (`hxl-fr-en`, CreatedDate 08/09, deploy KO `0Afdh00000A1E4nCAF`).
`language: en_GB` → ignoré, remplacé par `fr` (langue par défaut du pays ; seules les langues « fully
supported » sont acceptées pour une org, et en anglais il n'y a que `en_US`) → org fraîche, deploy OK
(`hxl-fr-engb`, `0AfEm00000ZUBhpKAH`). Une org **en anglais sort donc forcément du pool**. Compromis
retenu dans `createScratchOrg.sh` : org créée en `fr`, contrôle que `Organization.CreatedDate` est du
jour, bascule de l'admin en `en_US` (`User.LanguageLocaleKey`/`LocaleSidKey`, testé sur `hxl-fr-engb`),
puis 2 minutes d'attente avant le push.

**Le pool s'adapte à la demande** (16:06) : le run suivant de `createScratchOrg.sh` (def FR/fr) a tiré
`00DO800000YLbXHMA1` (USA268S), `CreatedDate` **14:56:46**, soit l'instant exact de la première demande
FR/fr de la journée (`hxl-texei-fr`, 14:56:38). Cette première demande a donc déclenché le remplissage
d'un pool FR/fr, et les 3 widgets ont échoué au push (`0AfO800000ZtnbqKAB`), puis 5 fois en retry.
L'astuce « langue inhabituelle » ne marche donc qu'une fois par langue et par instance, tant que le pool
correspondant n'est pas rempli. Contrôle du script resserré : `CreatedDate` doit dater de moins de
15 minutes, sinon org de pool. Sans solution déterministe côté définition : il faut une org dont le signup
a réellement eu lieu à la demande, et Salesforce ne l'expose pas comme option.

Quatrième point de mesure (voir aussi §17), org `lwc-in-agentforce-headless-experience-layer` (`00DVA00000JDqp32AD`, USA660S,
def `hxl-fresh`, hub `texei`) : signup 15:35:34, toggle 15:39:07, deploy du widget `hotelCard` à 15:40:47
→ **succès à +1 min 40 après le toggle**, +5 min après le signup. Avec les échecs à +28 s et +32 s, la
fenêtre se situe entre 35 s et 1 min 40 après le toggle. Toggle ou fin de signup comme déclencheur :
toujours indissociables, les deux étant espacés de 3 à 4 minutes sur toutes les orgs observées.

## 17. Voie MCP : Claude → serveur MCP hébergé de l'org → widget (2026-09-10, soir)

Org de travail : `hxl-fr-engb` (`00DEm00000WUiCTMA1`, Dev Hub `texei`, Winter '27, signup frais, démo
complète déployée, agent activé, org par défaut du projet). Objectif : Claude connecté via le serveur
MCP custom `restaurant-search-server` et le widget `restaurantList` rendu dans Claude (MCP Apps).

Sources officielles lues (via `r.jina.ai`) : guide HXL `hxl-mcp-server`, `hxl-mcp-setup-org`,
`hxl-mcp-setup-client`, `hxl-mcp-apex` ; guide Hosted MCP Servers `create-external-client-app`,
`claude`, `invocable-actions`, `client-connection-overview`.

### 17.1 Ce qui est fait (par métadonnées, sans Setup)

- `McpServerDefinition restaurantsearchserver` déjà dans l'org (push §16.4) : Tooling montre le tool
  `RestaurantServiceapex_RestaurantService` avec `UiResource=restaurantList` et la resource
  `ui://widget/lightningType/c__restaurantSearchMcpResult` (`McpServerToolDefinition`,
  `McpServerResourceDefinition`).
- **Classe Apex passée en `global`** (`RestaurantService`, méthode et inner classes) : la doc
  `invocable-actions` est explicite, « only Apex classes with a global method annotated
  @InvocableMethod can be exposed as MCP tools ». Le deploy du `McpServerDefinition` passait pourtant
  avec la classe `public` — le validateur ne vérifie pas ce point, c'est au runtime que ça se serait vu.
- **External Client App `HXL_Claude_MCP`** déployée via `scripts/hxl/setup-claude-mcp-app.sh` (même
  mécanique que §6bis) : callback `https://claude.ai/api/mcp/auth_callback`, scopes **`MCP, RefreshToken`**
  (noms métadonnées de `mcp_api`/`refresh_token` — appris par l'erreur du validateur qui liste les 37
  valeurs), `isNamedUserJwtEnabled=true`, `isPkceRequired=true`, `isConsumerSecretOptional=true`
  (client desktop public), pas de client credentials. La doc dit qu'on ne peut pas créer d'ECA en scratch
  org via Setup ; par Metadata API ça passe. Consumer key dans `scripts/hxl/.env` (gitignored).
- Activation du serveur MCP **impossible par API** : `McpServerAccess` (`McpServerId`, `Active`) existe
  en Tooling mais le POST renvoie `UNKNOWN_EXCEPTION`. Reste le bouton Activate dans Setup.

Pièges CLI rencontrés : (1) `sf project deploy start --source-dir` refuse un dossier hors projet
(`UnsafeFilepathError … unsafe character sequences`), et le chemin reste ensuite dans le tracking local
→ `sf project reset tracking` ; (2) des `.DS_Store` dans `uiWidgets/` font planter le deploy
(`ENOTDIR: not a directory, scandir …/uiWidgets/.DS_Store`) → supprimés, `**/.DS_Store` ajouté au
`.forceignore`.

### 17.2 Reste à faire côté Setup et Claude (manuel)

1. `sf org open -o hxl-fr-engb` → Setup → Quick Find « MCP » → **MCP Servers** (API Catalog) →
   `restaurant-search-server` → **Activate**. Noter l'**MCP Server URL** affichée. D'après le guide
   Claude, les scratch orgs utilisent le préfixe `sandbox` : attendu
   `https://api.salesforce.com/platform/mcp/v1/sandbox/custom/restaurantsearchserver`
   (TODO(unverified) : la forme exacte pour un serveur custom en scratch org, vérifier sur la page Setup).
2. Rester connecté à l'org dans le navigateur par défaut (l'OAuth de Claude y ouvre un onglet ; se
   déconnecter des autres orgs Salesforce avant, conseil de la doc).
3. Claude → Customize → Connectors → **+** → Add custom connector : nom libre, URL du serveur, Advanced
   settings → **OAuth Client ID** = `HXL_CLAUDE_MCP_CONSUMER_KEY` de `scripts/hxl/.env`, pas de secret.
   Connect → login Salesforce → Configure pour vérifier que le tool « Search Restaurants » est listé.
4. Prompt : « restaurants in Paris » → le tool renvoie le wrapper `c__restaurantSearchMcpResult`,
   Claude rend la resource `ui://widget/lightningType/c__restaurantSearchMcpResult` = widget
   `restaurantList`. Le bouton « Book a table » envoie un `sendMessage` dans la conversation Claude
   (§15.4) ; il n'y a pas d'action `Book_Restaurant` exposée au serveur MCP pour l'instant.
5. La doc prévient : l'ECA peut mettre jusqu'à 30 minutes à être utilisable avec `api.salesforce.com`
   (déployée à 16:22 UTC) ; et un widget modifié après un premier rendu met du temps à se rafraîchir
   côté client.

## 18. Dev org `devorg-2026` : rendu Agentforce enfin à l'écran, et trois surprises (2026-10-14)

Branche `hxl-widget` (main + widget, CLT HXL et MCP, McpServerDefinition, ECA). Deploy par lots sans erreur
(settings seuls, puis `force-app` : 41 composants), publish, post-push-source, permsets, data, activate.
Claude connecté au serveur MCP hébergé avec l'ECA : widget rendu dans Claude, champs remplis, bouton OK.

### 18.1 Output Rendering : Setup et `.agent` doivent dire la même chose, et seul Setup écrit l'action

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

### 18.2 Un SObject ne se sérialise pas pareil selon la surface

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

### 18.3 Le schéma d'un widget publié n'accepte que des ajouts

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

### 18.4 Sortie de crise : l'action vit dans le `.agent`, plus de GenAiFunction

L'Output Rendering de l'action ne pouvait plus être modifié dans Setup (liste vide). L'utilisateur a
supprimé le GenAiFunction `Search_Restaurants` dans Setup. La référence Agent Script des actions
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

## 19. Le bundle « hxl-widget-authoring » du Playground et le repo public sf-skills (2026-10-14)

Zip téléchargeable depuis le HXL Playground, déposé dans `docs/hxl-widget-authoring/` : un **skill au format
Claude Code** (`SKILL.md` + `references/` + `api/v68.0/`), version 0.0.1, sous Terms of Use Salesforce
(pas une licence open source : à ne pas redistribuer dans un repo public sans vérifier). Contenu :
méta-schéma du `schema.json` de widget, schéma JSON du payload de widget, un `.md` et un `.schema.json` par
composant `tile/*` (22 composants, index dans `component-index.md`), `expressions.md`, `icons.md` (liste
fermée, `star` et `calendar` y sont), `common-components.md`.

Ce qu'il apprend sur notre widget :

- **Méta-schéma** : un `lightning__objectType` exige `properties` **et** `additionalProperties: false` ; un
  `lightning__listType` exige `items` (déjà appris du validateur, §15.2). Notre `schema.json` est
  invalide sur les deux objets (`attributes` et `items`) : validé en local avec `ajv` (node_modules de
  Jest), le validateur de deploy ne l'exige pas. Ajouter `additionalProperties: false` sur le widget
  déployé est **refusé** comme breaking change, verbatim : `false is an invalid value for
  $.properties.attributes.properties.restaurants.items.additionalProperties. You can only change its
  value if its previous value didn't equal true. Otherwise, you can delete the keyword.` (absent = true).
  Donc même un resserrement du contrat exige la recréation du widget (§18.3) ; source remise à l'état
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
  à faire lors de la recréation propre du widget (§18.3), puisque changer `items` est un breaking change.
  Les noms de champs du widget doivent être **exactement** ceux de l'Apex (pas de renommage, pas de champ
  calculé) : confirme le choix DTO de §18.2, et interdit implicitement les SObjects comme items (aucune
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
  constats §18.1 et §18.4 restent de première main.

## 20. Recréation propre du widget sur la dev org (2026-10-15)

Objectif : sortir les cinq propriétés dépréciées du `schema.json` du widget (§18.3) et ajouter
`additionalProperties: false` sur `attributes` et `items` (§19), deux changements refusés comme
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
`lightning:type` sur les six types standards ; `@apexClassType/…` en `items` (doc sf-skills, §19) n'y
figure pas. Comme chaque changement d'`items` coûte une recréation, le widget garde des `items`
explicites, valides contre le méta-schéma, aux noms exactement ceux du DTO Apex. TODO(unverified) :
`items` en `@apexClassType/c__RestaurantService$Restaurant`, à essayer sur un widget jetable.

Non retesté dans cette session : rendu Agentforce (Output Rendering = `Restaurant HXL Response`) et rendu
dans Claude via le connecteur MCP. Le serveur MCP n'a pas été redéployé, son activation Setup devrait
être intacte.

Testé ensuite par l'utilisateur : rendu OK.
