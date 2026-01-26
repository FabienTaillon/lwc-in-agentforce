public with sharing class RestaurantService {
  @InvocableMethod(label='Search Restaurants' description='Search for available restaurants')
  public static List<RestaurantsResponse> searchRestaurants(List<RestaurantRequest> restaurantRequest) {
    System.debug('restaurantRequest: ' + restaurantRequest);
    List<Restaurant__c> restaurants = new List<Restaurant__c>();
    restaurants = [SELECT Id, NumberOfStars__c, TypeOfCuisine__c, PriceRange__c FROM Restaurant__c WHERE Address__City__s = :restaurantRequest.get(0).city WITH USER_MODE];

    RestaurantsResponse restaurantsResponse = new RestaurantsResponse();
    Restaurants restos = new Restaurants();
    restos.listRestaurants = restaurants;
    restaurantsResponse.restaurants = restos;
    return new List<restaurantsResponse>{ restaurantsResponse };
  }

  public class RestaurantRequest {
    @InvocableVariable (label='City')
    public String city;
  }
  
  public class RestaurantsResponse {
    @InvocableVariable
    public Restaurants restaurants;
  }

  public class Restaurants {
    public List<Restaurant__c> listRestaurants;
  }
}