# config hook path
git config core.hooksPath hooks
echo '##### CREATING SCRATCH ORG #####'
SCRATCH_ALIAS=$1
PROJECT_NAME=${PWD##*/}
SCRATCH_ALIAS="${SCRATCH_ALIAS:-$PROJECT_NAME-`git branch | grep \* | cut -d ' ' -f2`}" 
sf org create scratch --definition-file config/project-scratch-def.json --alias $SCRATCH_ALIAS --wait 15 --set-default
echo '##### PUSHING METADATA #####'
sf project deploy start --ignore-conflicts --target-org $SCRATCH_ALIAS
echo '##### TRUSTING THE ORG LIGHTNING DOMAIN #####'
# Agentforce replaces any URL outside the Trusted URLs allowlist with URL_Redacted, even the org's own domain, so the agent could not link to the booking record. The domain is org-specific, hence a CspTrustedSite generated here rather than kept in force-app.
LIGHTNING_DOMAIN=$(sf org display --target-org $SCRATCH_ALIAS --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'].replace('.my.salesforce.com', '.lightning.force.com'))")
rm -rf tmp-hxl-trusted && mkdir -p tmp-hxl-trusted/cspTrustedSites
sed "s|__LIGHTNING_DOMAIN__|${LIGHTNING_DOMAIN}|" scripts/cspTrustedSites/Org_Lightning_Domain.cspTrustedSite-meta.xml > tmp-hxl-trusted/cspTrustedSites/Org_Lightning_Domain.cspTrustedSite-meta.xml
sf project deploy start --source-dir tmp-hxl-trusted --ignore-conflicts --target-org $SCRATCH_ALIAS
rm -rf tmp-hxl-trusted
echo '##### PUBLISHING AGENT (AGENT SCRIPT BUNDLE) #####'
sf agent publish authoring-bundle --api-name Restaurant_Agent --skip-retrieve --target-org $SCRATCH_ALIAS
echo '##### DEPLOYING POST PUSH METADATA (ACTIVE LIGHTNING THEME, PERMSET REFERENCING AGENT) #####'
sf project deploy start --source-dir ./post-push-source --ignore-conflicts --target-org $SCRATCH_ALIAS
echo '##### ASSIGNING PERMISSIONS #####'
sf org assign permset --name Restaurants_Management --target-org $SCRATCH_ALIAS
sf org assign permset --name EinsteinGPTPromptTemplateManager --target-org $SCRATCH_ALIAS
echo '##### IMPORTING DUMMY DATA #####'
sf texei data import --inputdir ./data --target-org $SCRATCH_ALIAS
echo '##### CLEANING STANDARD LAYOUTS #####'
sf texei source layouts cleanorg --target-org $SCRATCH_ALIAS
echo '##### ACTIVATING AGENT #####'
sf agent activate --api-name Restaurant_Agent --target-org $SCRATCH_ALIAS
echo '##### ACTIVATING MCP SERVER #####'
# The McpServerDefinition deploys inactive; the API Catalog Connect REST API activates it (the Setup button does the same). The server URL is what the Claude custom connector needs.
API_VERSION=$(python3 -c "import json; print(json.load(open('sfdx-project.json'))['sourceApiVersion'])")
MCP_SERVER=$(sf agent mcp list --target-org $SCRATCH_ALIAS --json | python3 -c "import json,sys; s=[s for s in json.load(sys.stdin)['result']['mcpServers'] if s['name']=='restaurantsearchserver'][0]; print(s['id'], s['serverUrl'])")
sf api request rest "/services/data/v${API_VERSION}/api-catalog/mcp-servers/${MCP_SERVER%% *}/activate" --method POST --body '{}' --target-org $SCRATCH_ALIAS
echo "MCP server activated: ${MCP_SERVER#* }"
echo "Claude connector: Setup > External Client App Manager > HXL Claude MCP > OAuth Settings for the consumer key, then add a custom connector in Claude with the URL above and that key as OAuth Client ID."
echo '##### CLEANING TRACKING #####'
sf project reset tracking --no-prompt --target-org $SCRATCH_ALIAS
echo '##### OPENING SCRATCH ORG #####'
sf org open --path /lightning/app/c__Restaurants_Management --target-org $SCRATCH_ALIAS