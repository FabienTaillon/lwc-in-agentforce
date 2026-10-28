/**
 * Test data for the demo: restaurants and bookings only.
 */
@IsTest
public class TestDataFactory {
  public static Restaurant__c createRestaurant(String name, String city) {
    Restaurant__c restaurant = new Restaurant__c(
      Name = name,
      Address__City__s = city,
      NumberOfStars__c = '1',
      PriceRange__c = '€€€€',
      TypeOfCuisine__c = 'Creative'
    );
    insert restaurant;
    return restaurant;
  }

  public static Booking__c createBooking(Id restaurantId, Datetime bookingDateTime) {
    Booking__c booking = new Booking__c(
      Restaurant__c = restaurantId,
      BookingDateTime__c = bookingDateTime,
      SlotKey__c = restaurantId + '_' + bookingDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm')
    );
    insert booking;
    return booking;
  }
}
