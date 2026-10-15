// global: required so the invocable action is exposed as a tool by the hosted MCP server (API Catalog)
global with sharing class RestaurantService {
  @InvocableMethod(label='Search Restaurants' description='Search for available restaurants')
  global static List<RestaurantsResponse> searchRestaurants(List<RestaurantRequest> restaurantRequest) {
    System.debug('restaurantRequest: ' + restaurantRequest);
    List<Restaurant__c> restaurants = new List<Restaurant__c>();
    restaurants = [SELECT Id, Name, NumberOfStars__c, TypeOfCuisine__c, PriceRange__c FROM Restaurant__c WHERE Address__City__s = :restaurantRequest.get(0).city WITH USER_MODE];

    RestaurantsResponse restaurantsResponse = new RestaurantsResponse();
    Restaurants restos = new Restaurants();
    restos.listRestaurants = new List<Restaurant>();
    for (Restaurant__c record : restaurants) {
      restos.listRestaurants.add(new Restaurant(record));
    }
    restaurantsResponse.restaurants = restos;
    return new List<restaurantsResponse>{ restaurantsResponse };
  }

  global class RestaurantRequest {
    @InvocableVariable (label='City')
    global String city;
  }

  global class RestaurantsResponse {
    @InvocableVariable
    global Restaurants restaurants;
  }

  global class Restaurants {
    global List<Restaurant> listRestaurants;
  }

  // Plain DTO instead of the SObject: Agentforce serializes SObjects in UI API record form
  // (id, fields.Name.value) while the hosted MCP server sends flat JSON (Id, Name), so an
  // HXL widget cannot bind both. A DTO serializes the same way on every surface.
  // The LWC renderer only reads "id" and rehydrates the rest through LDS.
  global class Restaurant {
    global String id;
    global String name;
    global String stars;
    global String cuisine;
    global String priceRange;

    global Restaurant(Restaurant__c record) {
      this.id = record.Id;
      this.name = record.Name;
      this.stars = record.NumberOfStars__c;
      this.cuisine = record.TypeOfCuisine__c == null ? null : record.TypeOfCuisine__c.replace(';', ', ');
      this.priceRange = record.PriceRange__c;
    }
  }
}
