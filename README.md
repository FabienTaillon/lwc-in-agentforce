# LWC in Agentforce

This repo is a demo for Custom Lightning Types in Agentforce.  
This is linked to a talk delivered several times, including [Dreamforce 2025](https://speakerdeck.com/fabientaillon/dreamforce-2025-improve-agent-interactions-with-custom-lwcs-in-agentforce?slide=2).  
To create a demo Scratch Org, just install [texei-sfdx-plugin](https://github.com/texei/texei-sfdx-plugin) and run the `createScratchOrgScript.sh`.

## Notes on the Agent Script deployment order

The agent is defined with Agent Script in `force-app/main/default/aiAuthoringBundles/Restaurant_Agent`. A few things are worth knowing about how it deploys:

- Deploying the `AiAuthoringBundle` only stores it in the org: the agent (Bot) itself is created when running `sf agent publish authoring-bundle`. The script uses `--skip-retrieve`, otherwise the CLI pulls back org-specific generated metadata (planner bundles with record IDs, a `NextGen_<botId>` permission set, etc.) that shouldn't live in source control.
- The `Restaurants_Management` permission set grants access to the agent via `<agentAccesses>`, so it can only be deployed once the agent exists. That's why it lives in `post-push-source/` (deployed after `sf agent publish`) instead of `force-app/`.
- In the `.agent` file, the action attribute `source: "Search_Restaurants"` references the `GenAiFunction` of the same name, so `force-app/main/default/genAiFunctions/Search_Restaurants` is a required dependency and must be deployed before publishing the agent.