/**
 * Creates Booking__c records. One booking logic, two entry points:
 * - bookRestaurant: @InvocableMethod for the agent action Book_Restaurant (and the MCP tool).
 * - bookFromComponent: @AuraEnabled for the LWC modal, used by the demo modes where the UI
 *   books on its own, without the agent being aware.
 * The class is global so that the API Catalog can expose the invocable action as an MCP tool.
 */
global with sharing class BookRestaurantService {
  // ---- Shared logic ------------------------------------------------------------------------

  global class BookingResult {
    @AuraEnabled
    global Id bookingId;
    @AuraEnabled
    global String bookingReference;
    @AuraEnabled
    global String bookingUrl;
    @AuraEnabled
    global String restaurantName;
    @AuraEnabled
    global Datetime bookingDateTime;
    @AuraEnabled
    global String message;
  }

  global class BookingException extends Exception {
  }

  global static BookingResult createBooking(Id restaurantId, Datetime bookingDateTime) {
    List<Restaurant__c> restaurants = [
      SELECT Id, Name
      FROM Restaurant__c
      WHERE Id = :restaurantId
      WITH USER_MODE
      LIMIT 1
    ];
    if (restaurants.isEmpty()) {
      throw new BookingException('No restaurant found with Id ' + restaurantId + '. No booking was created.');
    }
    if (bookingDateTime == null) {
      throw new BookingException('A booking date and time is required. No booking was created.');
    }
    // Server-side guard shared by the three surfaces: a widget rendered minutes ago (or another
    // user) may target a slot that has been booked since.
    List<Booking__c> existing = [
      SELECT Name
      FROM Booking__c
      WHERE Restaurant__c = :restaurants[0].Id AND BookingDateTime__c = :bookingDateTime
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      throw new BookingException(
        'The ' +
          bookingDateTime.format('HH:mm') +
          ' slot at ' +
          restaurants[0].Name +
          ' on ' +
          bookingDateTime.format('d MMMM yyyy') +
          ' has just been booked (reference ' +
          existing[0].Name +
          '). Please pick another time. No booking was created.'
      );
    }

    Booking__c booking = new Booking__c(
      Restaurant__c = restaurants[0].Id,
      BookingDateTime__c = bookingDateTime,
      SlotKey__c = slotKey(restaurants[0].Id, bookingDateTime)
    );
    try {
      insert as user booking;
    } catch (DmlException e) {
      // Two transactions passed the check above at the same time: the unique SlotKey__c wins.
      if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        throw new BookingException(
          'The ' + bookingDateTime.format('HH:mm') + ' slot at ' + restaurants[0].Name + ' has just been booked by someone else. Please pick another time. No booking was created.'
        );
      }
      throw e;
    }
    booking = [SELECT Name FROM Booking__c WHERE Id = :booking.Id WITH USER_MODE];

    BookingResult result = new BookingResult();
    result.bookingId = booking.Id;
    result.bookingReference = booking.Name;
    result.bookingUrl = recordUrl(booking.Id, 'Booking__c');
    result.restaurantName = restaurants[0].Name;
    result.bookingDateTime = bookingDateTime;
    result.message =
      'Table booked at ' +
      restaurants[0].Name +
      ' for ' +
      bookingDateTime.format() +
      ' (reference ' +
      booking.Name +
      ').';
    return result;
  }

  /** Unique key of a slot: restaurant Id + date-time in UTC to the minute (see Booking__c.SlotKey__c). */
  @TestVisible
  private static String slotKey(Id restaurantId, Datetime bookingDateTime) {
    return restaurantId + '_' + bookingDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm');
  }

  /**
   * Full Lightning record URL. The agent cannot build one from a bare Id (it made up a
   * salesforce.rel link), and Agentforce replaces any URL whose domain is not trusted by
   * "URL_Redacted": the Lightning domain of the org (…lightning.force.com) is used rather than
   * the My Domain login URL (…my.salesforce.com) returned by URL.getOrgDomainUrl().
   */
  @TestVisible
  private static String recordUrl(Id recordId, String objectApiName) {
    String base = URL.getOrgDomainUrl().toExternalForm().replace('.my.salesforce.com', '.lightning.force.com');
    return base + '/lightning/r/' + objectApiName + '/' + recordId + '/view';
  }

  // ---- LWC entry point ---------------------------------------------------------------------

  /**
   * @param restaurantId Restaurant__c Id
   * @param bookingDate  calendar date, YYYY-MM-DD
   * @param bookingTime  time of day, HH:mm
   * Date and time are combined in the running user's time zone.
   */
  @AuraEnabled
  global static BookingResult bookFromComponent(Id restaurantId, String bookingDate, String bookingTime) {
    try {
      List<String> hm = bookingTime.split(':');
      Datetime bookingDateTime = Datetime.newInstance(
        Date.valueOf(bookingDate),
        Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0)
      );
      return createBooking(restaurantId, bookingDateTime);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ---- Agent entry point -------------------------------------------------------------------

  @InvocableMethod(label='Book Restaurant' description='Book a table at a restaurant for a given date and time')
  global static List<BookingResponse> bookRestaurant(List<BookingRequest> requests) {
    List<BookingResponse> responses = new List<BookingResponse>();
    for (BookingRequest request : requests) {
      BookingResponse response = new BookingResponse();
      try {
        BookingResult result = createBooking(request.restaurantId, parseIsoDateTime(request.bookingDateTime));
        response.bookingId = result.bookingId;
        response.bookingUrl = result.bookingUrl;
        response.bookingReference = result.bookingReference;
        response.confirmationMessage = result.message;
      } catch (BookingException e) {
        response.confirmationMessage = e.getMessage();
      } catch (Exception e) {
        response.confirmationMessage =
          'Could not understand the booking date and time "' +
          request.bookingDateTime +
          '". Please provide it in ISO 8601 format.';
      }
      responses.add(response);
    }
    return responses;
  }

  /**
   * The planner sends ISO 8601. With an offset or Z (2026-09-05T19:30:00Z) the instant is exact.
   * Without one (2026-10-16T10:00:00, what the planner sends for "10:00") the value is the user's
   * local time: JSON.deserialize would read it as UTC, so it is rebuilt in the user's time zone.
   */
  @TestVisible
  private static Datetime parseIsoDateTime(String iso) {
    Pattern localPattern = Pattern.compile('^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?$');
    Matcher m = localPattern.matcher(iso.trim());
    if (m.matches()) {
      return Datetime.newInstance(
        Date.newInstance(Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), Integer.valueOf(m.group(3))),
        Time.newInstance(
          Integer.valueOf(m.group(4)),
          Integer.valueOf(m.group(5)),
          m.group(6) == null ? 0 : Integer.valueOf(m.group(6)),
          0
        )
      );
    }
    return (Datetime) JSON.deserialize('"' + iso.trim() + '"', Datetime.class);
  }

  global class BookingRequest {
    @InvocableVariable(
      label='Restaurant Id'
      description='Salesforce Id of the restaurant to book. It is included in the "Book a table at ..." message sent by the restaurant list.'
      required=true
    )
    global String restaurantId;

    @InvocableVariable(
      label='Booking Date and Time'
      description='Date and time of the booking in ISO 8601 format. Ask the user for the date and the time if they are not given.'
      required=true
    )
    global String bookingDateTime;
  }

  global class BookingResponse {
    @InvocableVariable(label='Confirmation Message' description='Confirmation or error message of the booking')
    global String confirmationMessage;

    @InvocableVariable(label='Booking Reference' description='Reference number of the created booking')
    global String bookingReference;

    @InvocableVariable(label='Booking Id' description='Salesforce record Id of the created booking')
    global String bookingId;

    @InvocableVariable(label='Booking URL' description='Link to the created booking record. Show this exact URL to the user, do not build another one.')
    global String bookingUrl;
  }
}
