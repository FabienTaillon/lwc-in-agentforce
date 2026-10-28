@IsTest
private class AgentforcePanelControllerTest {
  @IsTest
  static void shouldReturnNull_WhenAgentDoesNotExist() {
    Test.startTest();
    Id botId = AgentforcePanelController.getBotId('No_Such_Agent');
    Test.stopTest();

    Assert.isNull(botId, 'Unknown agent');
  }

  @IsTest
  static void shouldReturnTheBotId_OfTheDemoAgent() {
    // BotDefinition is setup metadata, not test data: compare with what the org returns.
    List<BotDefinition> bots = [SELECT Id FROM BotDefinition WHERE DeveloperName = 'Restaurant_Agent' LIMIT 1];
    Id expected = bots.isEmpty() ? null : bots[0].Id;

    Test.startTest();
    Id botId = AgentforcePanelController.getBotId('Restaurant_Agent');
    Test.stopTest();

    Assert.areEqual(expected, botId, 'Id of the Restaurant_Agent bot');
  }
}
