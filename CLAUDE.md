# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commandes

```bash
# Créer un scratch org de démo complet (nécessite texei-sfdx-plugin)
./createScratchOrg.sh [alias]   # alias par défaut : <nom-projet>-<branche>

# Déploiement manuel (ordre OBLIGATOIRE, voir ci-dessous)
sf project deploy start --ignore-conflicts
sf agent publish authoring-bundle --api-name Restaurant_Agent --skip-retrieve
sf project deploy start --source-dir ./post-push-source --ignore-conflicts

# Tests LWC (Jest)
npm run test:unit                                   # tous les tests
npm run test:unit -- restaurantDetails              # un seul composant
npm run test:unit:watch
npm run test:unit:coverage

# Lint / format
npm run lint                    # ESLint sur aura/lwc
npm run prettier:verify         # prettier --write via "npm run prettier"
```

### Ordre de déploiement - critique

1. `force-app/` d'abord : déployer l'`AiAuthoringBundle` ne fait que le **stocker** dans l'org. L'Apex, les objets, les CLT et le widget doivent y être avant publication. Il n'y a **pas** de `GenAiFunction` en source : l'action `Search_Restaurants` est entièrement définie dans le `.agent` (`target: "apex://RestaurantService"`, sans `source:`) et le publish la génère dans l'agent, sans créer d'asset dans Agentforce Assets → Actions.
2. `sf agent publish authoring-bundle` crée le Bot. Toujours passer `--skip-retrieve`, sinon le CLI rapatrie des métadonnées générées spécifiques à l'org (genAiPlannerBundles avec IDs, permset `NextGen_<botId>`, cspTrustedSites `Voice_*`) qui n'ont rien à faire en source control.
3. `post-push-source/` ensuite : le permset `Restaurants_Management` contient `<agentAccesses>` et ne peut se déployer qu'une fois le Bot créé. C'est pour ça qu'il vit hors de `force-app/`.

Sur une org non-scratch (dev org), deux pièges supplémentaires : un deploy avec une erreur est annulé en bloc, et les `LightningTypeBundle` échouent avec une erreur générique dès qu'un autre composant du même lot est en erreur. Déployer par lots sains (settings, puis le reste). Détails dans `docs/hxl-migration-notes.md` §6.5.

## Architecture - chaîne de rendu CLT

Le cœur de la démo est la chaîne qui va de l'action de l'agent au rendu LWC :

1. **Agent Script** ([Restaurant_Agent.agent](force-app/main/default/aiAuthoringBundles/Restaurant_Agent/Restaurant_Agent.agent)) : le subagent `Restaurant_Management` déclare l'action `Search_Restaurants` avec `target: "apex://RestaurantService"` (pas de `source:`, donc pas de GenAiFunction). Sa sortie `restaurants` déclare `complex_data_type_name: "c__restaurantResponse"`.
2. **Type de sortie** : la ligne `complex_data_type_name` du `.agent` est la seule source du rendu. La changer vers `c__restaurantHxlResponse` puis `sf agent publish` + `sf agent activate` (chaque publish crée une version inactive) bascule le rendu vers le widget HXL. Ne pas réintroduire de `GenAiFunction` avec `source:` : son `output/schema.json` ne se met plus à jour par deploy une fois créé, et le publish refuse tout désaccord avec le `.agent` (journal §8.1).
3. **Apex** ([RestaurantService.cls](force-app/main/default/classes/RestaurantService.cls)) : `@InvocableMethod` qui interroge `Restaurant__c` par ville. La classe interne `Restaurants` est la source de vérité du schéma. La classe est `global` : obligatoire pour que l'API Catalog l'expose comme tool MCP. `BookRestaurantService` suit le même modèle pour la réservation (`Booking__c`) : `@InvocableMethod` pour l'action `Book_Restaurant` du `.agent` et le second tool MCP, `@AuraEnabled bookFromComponent` pour la modal LWC (journal §12) ; garde serveur « créneau déjà pris » + champ unique `Booking__c.SlotKey__c`. `RestaurantAvailabilityService` idem pour les créneaux disponibles (action `Get_Availability`, tool MCP, `getSlots` pour la modal), rendus par le widget HXL `restaurantSlots` via les CLT `restaurantAvailability` (Agentforce) et `restaurantAvailabilityMcpResult` + `restaurantAvailabilityPayload` (MCP), journal §13.
4. **LightningTypeBundle** (`lightningTypes/restaurantResponse/`) : `schema.json` pointe vers `"@apexClassType/c__RestaurantService$Restaurants"` ; `lightningDesktopGenAi/renderer.json` remplace le rendu racine (`"$"`) par `c/restaurantDetails`.
5. **LWC** : `restaurantDetails` reçoit l'objet via `@api value`, ré-hydrate les enregistrements via LDS (`getRecords`), et ouvre `restaurantBookingModal` (LightningModal). La modal ne réserve pas : elle renvoie « Book a table at … on <date> at <heure> » à l'agent via `lightning/accApi` `execute(utterance, botId)`, le `botId` étant résolu par `AgentforcePanelController.getBotId` (journal §11). Sous-composants : `restaurantBooking`, `michelinStar`, `michelinStarDisplay`.

Données de démo : `data/1-Restaurant__c.json` (import via `sf texei data import`). Le scratch org def active `Einstein1AIPlatform`, `einsteinGptSettings` et `agentPlatformSettings`.

## HXL (Headless Experience Layer) : le même résultat rendu par un widget

Ajout additif à la démo CLT/LWC. Le schéma Apex reste la source de vérité, seul le rendu change.

- **Widget** `uiWidgets/restaurantList/` (`UiWidgetBundle`, JSON) : `meta.forEach` sur l'attribut `restaurants`, un bloc par restaurant (nom, prix, étoiles, cuisine) et un `tile/button` « Book a table » → `action/sendMessage`. Le `schema.json` déclare l'attribut (`lightning__listType` avec sous-schéma `items`, exigé par le validateur).
- **Rendu Agentforce** : CLT `lightningTypes/restaurantHxlResponse/`, même `@apexClassType` que `restaurantResponse`, avec un `renderer.json` **à la racine** (multi-surface) vers `@widget/c/restaurantList`. Bascule LWC ↔ widget : `complex_data_type_name` du `.agent` (`c__restaurantResponse` = LWC, `c__restaurantHxlResponse` = widget), deploy du bundle, `sf agent publish authoring-bundle`, `sf agent activate`.
- **Rendu MCP (Claude, ChatGPT)** : `mcpServerDefinitions/restaurantsearchserver` expose les deux actions Apex via l'API Catalog (tools `RestaurantServiceapex_RestaurantService`, `RestaurantAvailabilityServiceapex_RestaurantAvailabilityService` avec le widget `restaurantSlots`, et `BookRestaurantServiceapex_BookRestaurantService` sans widget) avec la resource `ui://widget/lightningType/c__restaurantSearchMcpResult`. Les deux CLT « rôle MCP » (`restaurantSearchMcpResult` = enveloppe invocable, `restaurantSearchPayload` = outputValues) portent `lightning:tags: ["mcp"]` ; le renderer de l'enveloppe mappe `outputValues.restaurants.listRestaurants` vers l'attribut du widget.
- **Liens dans les réponses de l'agent** : toute URL hors de l'allowlist Trusted URLs est remplacée par `URL_Redacted`, domaine Lightning de l'org compris. `createScratchOrg.sh` déploie un `CspTrustedSite` pour le domaine Lightning de l'org, généré depuis le modèle `scripts/cspTrustedSites/` (placeholder `__LIGHTNING_DOMAIN__`, URL spécifique à l'org donc rien de déployable en source ; sur une dev org, le faire à la main dans Setup → Trusted URLs ; journal §12.1).
- **Gate org** : `uiWidgetSettings.hxlEnabled` dans `config/project-scratch-def.json` (plus de fichier settings en source ; sur une dev org, activer le toggle dans Setup → Headless Experience Layer Settings). Sans lui, « Not available for deploy for this organization ».
- **External Client App** `HXL_Claude_MCP` en source (`externalClientApps/`, `extlClntAppGlobalOauthSets/`, `extlClntAppOauthSettings/`, `extlClntAppOauthPolicies/`) : callback Claude, PKCE, JWT, secret optionnel, scopes `MCP, RefreshToken`. Le global OAuth settings est committé **sans** `consumerKey` ni `consumerSecret` : l'org les génère au premier deploy et les conserve aux redeploys (vérifié, journal §14). Ne pas rapatrier ce fichier avec ses clés dans `force-app/`.
- **Activation du serveur MCP** : le `McpServerDefinition` se déploie inactif. `createScratchOrg.sh` l'active via l'API Catalog Connect REST API (`POST /services/data/vXX.0/api-catalog/mcp-servers/{id}/activate`, 204, idempotent ; l'id et l'URL du serveur viennent de `sf agent mcp list --json`). Sur une dev org, même appel, ou Setup → MCP Servers → Activate.
- **Côté Setup, manuel** : lire la consumer key dans Setup → External Client App Manager → HXL Claude MCP → OAuth Settings. Connecteur custom Claude = URL du serveur + cette consumer key, pas de secret.

Journal complet (erreurs verbatim, impasses, sources officielles) : `docs/hxl-migration-notes.md`. Doc officielle : https://developer.salesforce.com/docs/platform/hxl/guide/get-started.html (lisible via `r.jina.ai`, curl direct = 403).

## Contraintes

- Ne rien casser de la démo LWC existante : tout ajout HXL reste additif.
- Ne pas committer de credentials ni d'IDs d'org.
- En cas de doute sur la syntaxe des widgets : la doc officielle plutôt qu'improviser ; si introuvable, `TODO(unverified)`.
- Demander avant toute opération destructive (suppression de métadonnées, recréation d'org).
