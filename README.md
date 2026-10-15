# LWC in Agentforce

This repo is a demo for Custom Lightning Types in Agentforce.  
This is linked to a talk delivered several times, including [Dreamforce 2025](https://speakerdeck.com/fabientaillon/dreamforce-2025-improve-agent-interactions-with-custom-lwcs-in-agentforce?slide=2).  
To create a demo Scratch Org, just install [texei-sfdx-plugin](https://github.com/texei/texei-sfdx-plugin) and run the `createScratchOrgScript.sh`.

## Notes on the Agent Script deployment order

The agent is defined with Agent Script in `force-app/main/default/aiAuthoringBundles/Restaurant_Agent`. A few things are worth knowing about how it deploys:

- Deploying the `AiAuthoringBundle` only stores it in the org: the agent (Bot) itself is created when running `sf agent publish authoring-bundle`. The script uses `--skip-retrieve`, otherwise the CLI pulls back org-specific generated metadata (planner bundles with record IDs, a `NextGen_<botId>` permission set, etc.) that shouldn't live in source control.
- The `Restaurants_Management` permission set grants access to the agent via `<agentAccesses>`, so it can only be deployed once the agent exists. That's why it lives in `post-push-source/` (deployed after `sf agent publish`) instead of `force-app/`.
- The `Search_Restaurants` action is defined entirely in the `.agent` file (`target: "apex://RestaurantService"`, no `source:`), so there is no `GenAiFunction` in source: publishing the agent generates the action inside the agent. The output type (`complex_data_type_name`) is the Lightning type that decides the rendering: `c__restaurantResponse` (LWC) or `c__restaurantHxlResponse` (HXL widget). Each publish creates a new inactive version, so run `sf agent activate` afterwards.