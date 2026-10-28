@IsTest
private class RestaurantServiceTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createRestaurant('Le Jardin', 'Paris');
    TestDataFactory.createRestaurant('Blind', 'Porto');
  }

  @IsTest
  static void shouldReturnRestaurantsOfTheCity() {
    RestaurantService.RestaurantRequest request = new RestaurantService.RestaurantRequest();
    request.city = 'Paris';

    Test.startTest();
    List<RestaurantService.RestaurantsResponse> responses = RestaurantService.searchRestaurants(
      new List<RestaurantService.RestaurantRequest>{ request }
    );
    Test.stopTest();

    Assert.areEqual(1, responses.size(), 'One response per request');
    List<RestaurantService.Restaurant> restaurants = responses[0].restaurants.listRestaurants;
    Assert.areEqual(1, restaurants.size(), 'Only the Paris restaurant is returned');
    Assert.areEqual('Le Jardin', restaurants[0].name, 'Restaurant name');
    Assert.areEqual('1', restaurants[0].stars, 'Stars come from NumberOfStars__c');
    Assert.areEqual('Creative', restaurants[0].cuisine, 'Cuisine comes from TypeOfCuisine__c');
  }

  @IsTest
  static void shouldReturnEmptyList_WhenNoRestaurantInTheCity() {
    RestaurantService.RestaurantRequest request = new RestaurantService.RestaurantRequest();
    request.city = 'Lyon';

    Test.startTest();
    List<RestaurantService.RestaurantsResponse> responses = RestaurantService.searchRestaurants(
      new List<RestaurantService.RestaurantRequest>{ request }
    );
    Test.stopTest();

    Assert.areEqual(0, responses[0].restaurants.listRestaurants.size(), 'No restaurant in Lyon');
  }
}
