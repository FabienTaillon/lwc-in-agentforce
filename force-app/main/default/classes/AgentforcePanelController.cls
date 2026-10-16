/**
 * Resolves an agent's BotDefinition Id from its API name, so that LWCs rendered in the
 * Agentforce panel can call lightning/accApi execute(utterance, botId) without hardcoding
 * an org-specific Id.
 */
public with sharing class AgentforcePanelController {
  @AuraEnabled(cacheable=true)
  public static Id getBotId(String developerName) {
    List<BotDefinition> bots = [
      SELECT Id
      FROM BotDefinition
      WHERE DeveloperName = :developerName
      WITH USER_MODE
      LIMIT 1
    ];
    return bots.isEmpty() ? null : bots[0].Id;
  }
}
