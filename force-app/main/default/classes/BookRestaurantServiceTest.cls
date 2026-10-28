@IsTest
private class BookRestaurantServiceTest {
  private static final Datetime SLOT = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(19, 30, 0, 0));

  @TestSetup
  static void setup() {
    TestDataFactory.createRestaurant('Le Jardin', 'Paris');
  }

  private static Restaurant__c restaurant() {
    return [SELECT Id, Name FROM Restaurant__c LIMIT 1];
  }

  @IsTest
  static void shouldCreateBooking_WhenSlotIsFree() {
    BookRestaurantService.BookingRequest request = new BookRestaurantService.BookingRequest();
    request.restaurantId = restaurant().Id;
    request.bookingDateTime = SLOT.format('yyyy-MM-dd\'T\'HH:mm:ss');

    Test.startTest();
    List<BookRestaurantService.BookingResponse> responses = BookRestaurantService.bookRestaurant(
      new List<BookRestaurantService.BookingRequest>{ request }
    );
    Test.stopTest();

    BookRestaurantService.BookingResponse response = responses[0];
    Assert.isNotNull(response.bookingId, 'A booking is created');
    Assert.isTrue(response.confirmationMessage.startsWith('Table booked at Le Jardin'), 'Confirmation message');
    Assert.isTrue(response.bookingUrl.contains('/lightning/r/Booking__c/' + response.bookingId), 'Record URL');
    Booking__c booking = [SELECT BookingDateTime__c FROM Booking__c WHERE Id = :response.bookingId];
    Assert.areEqual(SLOT, booking.BookingDateTime__c, 'Booked at the requested local time');
  }

  @IsTest
  static void shouldRefuseBooking_WhenSlotIsAlreadyTaken() {
    TestDataFactory.createBooking(restaurant().Id, SLOT);
    BookRestaurantService.BookingRequest request = new BookRestaurantService.BookingRequest();
    request.restaurantId = restaurant().Id;
    request.bookingDateTime = SLOT.format('yyyy-MM-dd\'T\'HH:mm:ss');

    Test.startTest();
    List<BookRestaurantService.BookingResponse> responses = BookRestaurantService.bookRestaurant(
      new List<BookRestaurantService.BookingRequest>{ request }
    );
    Test.stopTest();

    Assert.isNull(responses[0].bookingId, 'No booking is created');
    Assert.isTrue(responses[0].confirmationMessage.contains('has just been booked'), 'Explains the slot is taken');
    Assert.areEqual(1, [SELECT COUNT() FROM Booking__c], 'Still one booking');
  }

  @IsTest
  static void shouldReturnErrorMessage_WhenDateIsNotIso() {
    BookRestaurantService.BookingRequest request = new BookRestaurantService.BookingRequest();
    request.restaurantId = restaurant().Id;
    request.bookingDateTime = 'tomorrow evening';

    Test.startTest();
    List<BookRestaurantService.BookingResponse> responses = BookRestaurantService.bookRestaurant(
      new List<BookRestaurantService.BookingRequest>{ request }
    );
    Test.stopTest();

    Assert.isNull(responses[0].bookingId, 'No booking is created');
    Assert.isTrue(responses[0].confirmationMessage.contains('ISO 8601'), 'Asks for an ISO date');
  }

  @IsTest
  static void shouldCreateBooking_FromComponent() {
    Test.startTest();
    BookRestaurantService.BookingResult result = BookRestaurantService.bookFromComponent(
      restaurant().Id,
      String.valueOf(SLOT.date()),
      '19:30'
    );
    Test.stopTest();

    Assert.isNotNull(result.bookingId, 'A booking is created');
    Assert.areEqual('Le Jardin', result.restaurantName, 'Restaurant name');
    Assert.areEqual(SLOT, result.bookingDateTime, 'Date and time combined in the user time zone');
  }

  @IsTest
  static void shouldThrowAuraHandledException_WhenRestaurantDoesNotExist() {
    Restaurant__c deleted = restaurant();
    delete deleted;

    Test.startTest();
    try {
      BookRestaurantService.bookFromComponent(deleted.Id, String.valueOf(SLOT.date()), '19:30');
      Assert.fail('Expected an AuraHandledException');
    } catch (AuraHandledException e) {
      // The message is not readable in tests (AuraHandledException returns "Script-thrown exception").
      Assert.areEqual(0, [SELECT COUNT() FROM Booking__c], 'No booking is created');
    }
    Test.stopTest();
  }

  @IsTest
  static void shouldReadIsoWithoutOffset_AsUserLocalTime() {
    Test.startTest();
    Datetime parsed = BookRestaurantService.parseIsoDateTime('2026-10-16T10:00:00');
    Test.stopTest();

    Assert.areEqual(
      Datetime.newInstance(Date.newInstance(2026, 10, 16), Time.newInstance(10, 0, 0, 0)),
      parsed,
      '10:00 without offset is 10:00 in the user time zone'
    );
  }
}
