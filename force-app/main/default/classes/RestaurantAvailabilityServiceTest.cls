@IsTest
private class RestaurantAvailabilityServiceTest {
  private static final Date DAY = Date.today().addDays(1);

  @TestSetup
  static void setup() {
    TestDataFactory.createRestaurant('Le Jardin', 'Paris');
  }

  private static Restaurant__c restaurant() {
    return [SELECT Id, Name FROM Restaurant__c LIMIT 1];
  }

  @IsTest
  static void shouldReturnAllOpeningSlots_WhenNothingIsBooked() {
    Test.startTest();
    RestaurantAvailabilityService.Availability availability = RestaurantAvailabilityService.getSlots(
      restaurant().Id,
      String.valueOf(DAY)
    );
    Test.stopTest();

    Assert.areEqual(RestaurantAvailabilityService.OPENING_SLOTS.size(), availability.slots.size(), 'All opening slots are free');
    Assert.isTrue(availability.hasSlots, 'hasSlots');
    Assert.isFalse(availability.hasNoSlots, 'hasNoSlots');
    Assert.areEqual(String.valueOf(DAY), availability.bookingDate, 'Requested date');
  }

  @IsTest
  static void shouldExcludeBookedSlot() {
    TestDataFactory.createBooking(restaurant().Id, Datetime.newInstance(DAY, Time.newInstance(19, 30, 0, 0)));

    Test.startTest();
    RestaurantAvailabilityService.Availability availability = RestaurantAvailabilityService.getSlots(
      restaurant().Id,
      String.valueOf(DAY)
    );
    Test.stopTest();

    Assert.areEqual(RestaurantAvailabilityService.OPENING_SLOTS.size() - 1, availability.slots.size(), 'One slot less');
    for (RestaurantAvailabilityService.Slot slot : availability.slots) {
      Assert.areNotEqual('19:30', slot.startTime, 'The booked slot is not offered');
    }
  }

  @IsTest
  static void shouldFindRestaurantByName_FromAgent() {
    RestaurantAvailabilityService.AvailabilityRequest request = new RestaurantAvailabilityService.AvailabilityRequest();
    request.restaurantName = 'jardin';
    request.bookingDate = String.valueOf(DAY);

    Test.startTest();
    List<RestaurantAvailabilityService.AvailabilityResponse> responses = RestaurantAvailabilityService.getAvailability(
      new List<RestaurantAvailabilityService.AvailabilityRequest>{ request }
    );
    Test.stopTest();

    Assert.areEqual('Le Jardin', responses[0].availability.restaurantName, 'Found by partial name');
    Assert.isTrue(responses[0].message.contains('available time slot(s) at Le Jardin'), 'Summary message');
  }

  @IsTest
  static void shouldReturnErrorMessage_WhenRestaurantIsUnknown() {
    RestaurantAvailabilityService.AvailabilityRequest request = new RestaurantAvailabilityService.AvailabilityRequest();
    request.restaurantName = 'Nowhere';
    request.bookingDate = String.valueOf(DAY);

    Test.startTest();
    List<RestaurantAvailabilityService.AvailabilityResponse> responses = RestaurantAvailabilityService.getAvailability(
      new List<RestaurantAvailabilityService.AvailabilityRequest>{ request }
    );
    Test.stopTest();

    Assert.isNull(responses[0].availability, 'No availability');
    Assert.isTrue(responses[0].message.contains('No restaurant found'), 'Explains the restaurant is unknown');
  }
}
