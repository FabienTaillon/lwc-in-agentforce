#!/bin/bash
# Deploys an External Client App (ECA) that Claude uses as a custom connector
# against the org's hosted MCP server (restaurant-search-server, see
# force-app/main/default/mcpServerDefinitions/). Follows the Hosted MCP Servers
# guide (create-external-client-app): callback = Claude, scopes mcp_api +
# refresh_token (named "MCP" and "RefreshToken" in metadata — the deploy
# validator lists the valid names when you get one wrong), JWT access tokens
# for named users, PKCE required, no client secret (public desktop client).
# ECAs deploy fine in scratch orgs through the Metadata API even though the
# Setup UI refuses to create them there.
# The consumer key is written to scripts/hxl/.env (gitignored) — never committed.
# Usage: scripts/hxl/setup-claude-mcp-app.sh [org alias]   (default: project default org)
set -e

ORG_FLAG=""
[ -n "$1" ] && ORG_FLAG="--target-org $1"
MY_DOMAIN=$(sf org display $ORG_FLAG --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
CONSUMER_KEY="HxlClaude$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 60)"
CONSUMER_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)

# Must live inside the project: the CLI rejects paths outside it ("unsafe character sequences").
WORK=tmp-hxl-claude-app
rm -rf $WORK
mkdir -p $WORK/externalClientApps $WORK/extlClntAppGlobalOauthSets $WORK/extlClntAppOauthSettings $WORK/extlClntAppOauthPolicies

cat > $WORK/externalClientApps/HXL_Claude_MCP.eca-meta.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<ExternalClientApplication xmlns="http://soap.sforce.com/2006/04/metadata">
    <contactEmail>demo@example.com</contactEmail>
    <description>Claude custom connector for the restaurant-search-server hosted MCP server (HXL widget demo)</description>
    <distributionState>Local</distributionState>
    <label>HXL Claude MCP</label>
</ExternalClientApplication>
XML

cat > $WORK/extlClntAppGlobalOauthSets/HXL_Claude_MCP_glbl.ecaGlblOauth-meta.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<ExtlClntAppGlobalOauthSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <callbackUrl>https://claude.ai/api/mcp/auth_callback</callbackUrl>
    <consumerKey>${CONSUMER_KEY}</consumerKey>
    <consumerSecret>${CONSUMER_SECRET}</consumerSecret>
    <externalClientApplication>HXL_Claude_MCP</externalClientApplication>
    <isClientCredentialsFlowEnabled>false</isClientCredentialsFlowEnabled>
    <isConsumerSecretOptional>true</isConsumerSecretOptional>
    <isIntrospectAllTokens>false</isIntrospectAllTokens>
    <isNamedUserJwtEnabled>true</isNamedUserJwtEnabled>
    <isPkceRequired>true</isPkceRequired>
    <label>HXL Claude MCP Global OAuth</label>
</ExtlClntAppGlobalOauthSettings>
XML

cat > $WORK/extlClntAppOauthSettings/HXL_Claude_MCP_oauth.ecaOauth-meta.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<ExtlClntAppOauthSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <commaSeparatedOauthScopes>MCP, RefreshToken</commaSeparatedOauthScopes>
    <externalClientApplication>HXL_Claude_MCP</externalClientApplication>
    <label>HXL Claude MCP OAuth Settings</label>
</ExtlClntAppOauthSettings>
XML

cat > $WORK/extlClntAppOauthPolicies/HXL_Claude_MCP_plcy.ecaOauthPlcy-meta.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<ExtlClntAppOauthConfigurablePolicies xmlns="http://soap.sforce.com/2006/04/metadata">
    <externalClientApplication>HXL_Claude_MCP</externalClientApplication>
    <isClientCredentialsFlowEnabled>false</isClientCredentialsFlowEnabled>
    <label>HXL Claude MCP OAuth Policies</label>
    <permittedUsersPolicyType>AllSelfAuthorized</permittedUsersPolicyType>
</ExtlClntAppOauthConfigurablePolicies>
XML

echo '##### DEPLOYING EXTERNAL CLIENT APP FOR CLAUDE #####'
sf project deploy start --source-dir $WORK --ignore-conflicts $ORG_FLAG

cat >> scripts/hxl/.env <<ENV
HXL_CLAUDE_MCP_CONSUMER_KEY=${CONSUMER_KEY}
HXL_CLAUDE_MCP_MY_DOMAIN=${MY_DOMAIN}
ENV
rm -rf $WORK
echo "Consumer key appended to scripts/hxl/.env (gitignored)."
echo "Next: Setup > MCP Servers > restaurant-search-server > Activate (note the MCP Server URL),"
echo "then Claude > Customize > Connectors > Add custom connector: that URL + OAuth Client ID = consumer key."
echo "The ECA can take up to 30 minutes to become usable with api.salesforce.com."
