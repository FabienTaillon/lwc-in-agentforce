/**
 * Available time slots of a restaurant for a given day: the reference opening slots minus the
 * existing Booking__c records. Single source of truth for the three surfaces:
 * - getSlots: @AuraEnabled for the LWC booking modal (one call per day displayed, not cached).
 * - getAvailability: @InvocableMethod for the agent action Get_Availability and the MCP tool,
 *   rendered by the HXL widget restaurantSlots (CLT c__restaurantAvailability).
 * The class is global so that the API Catalog can expose the invocable action as an MCP tool.
 */
global with sharing class RestaurantAvailabilityService {
  // Demo opening slots. In real life this would come from the restaurant's opening hours.
  @TestVisible
  private static final List<String> OPENING_SLOTS = new List<String>{
    '12:00',
    '12:30',
    '13:00',
    '13:30',
    '19:00',
    '19:30',
    '20:00',
    '20:30',
    '21:00'
  };

  // ---- Shared logic ------------------------------------------------------------------------

  global class Availability {
    @AuraEnabled
    global String restaurantId;
    @AuraEnabled
    global String restaurantName;
    /** Calendar date, YYYY-MM-DD */
    @AuraEnabled
    global String bookingDate;
    /** Same date formatted for display in the user's locale */
    @AuraEnabled
    global String bookingDateLabel;
    @AuraEnabled
    global Boolean hasSlots;
    /** Convenience for widget conditions (no negation operator in HXL expressions) */
    @AuraEnabled
    global Boolean hasNoSlots;
    @AuraEnabled
    global List<Slot> slots;
  }

  global class Slot {
    /** HH:mm in the user's time zone */
    @AuraEnabled
    global String startTime;
  }

  global class AvailabilityException extends Exception {
  }

  global static Availability getAvailableSlots(Id restaurantId, String restaurantName, Date day) {
    Restaurant__c restaurant = findRestaurant(restaurantId, restaurantName);
    if (day == null) {
      throw new AvailabilityException('A date is required to check availability.');
    }

    // Day boundaries in the running user's time zone
    Datetime dayStart = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    Datetime dayEnd = dayStart.addDays(1);
    Set<String> taken = new Set<String>();
    for (Booking__c booking : [
      SELECT BookingDateTime__c
      FROM Booking__c
      WHERE Restaurant__c = :restaurant.Id AND BookingDateTime__c >= :dayStart AND BookingDateTime__c < :dayEnd
      WITH USER_MODE
    ]) {
      taken.add(booking.BookingDateTime__c.format('HH:mm'));
    }

    Availability availability = new Availability();
    availability.restaurantId = restaurant.Id;
    availability.restaurantName = restaurant.Name;
    availability.bookingDate = String.valueOf(day);
    availability.bookingDateLabel = dayStart.format('EEEE d MMMM yyyy');
    availability.slots = new List<Slot>();
    for (String opening : OPENING_SLOTS) {
      if (!taken.contains(opening)) {
        Slot slot = new Slot();
        slot.startTime = opening;
        availability.slots.add(slot);
      }
    }
    availability.hasSlots = !availability.slots.isEmpty();
    availability.hasNoSlots = availability.slots.isEmpty();
    return availability;
  }

  private static Restaurant__c findRestaurant(Id restaurantId, String restaurantName) {
    List<Restaurant__c> restaurants;
    if (restaurantId != null) {
      restaurants = [SELECT Id, Name FROM Restaurant__c WHERE Id = :restaurantId WITH USER_MODE LIMIT 1];
    } else if (String.isNotBlank(restaurantName)) {
      String pattern = '%' + String.escapeSingleQuotes(restaurantName.trim()) + '%';
      restaurants = [SELECT Id, Name FROM Restaurant__c WHERE Name LIKE :pattern WITH USER_MODE ORDER BY Name LIMIT 1];
    } else {
      throw new AvailabilityException('A restaurant Id or a restaurant name is required.');
    }
    if (restaurants.isEmpty()) {
      throw new AvailabilityException(
        'No restaurant found for "' + (restaurantId != null ? String.valueOf(restaurantId) : restaurantName) + '".'
      );
    }
    return restaurants[0];
  }

  // ---- LWC entry point ---------------------------------------------------------------------

  /** Not cacheable on purpose: availability changes with every booking. */
  @AuraEnabled
  global static Availability getSlots(Id restaurantId, String bookingDate) {
    try {
      return getAvailableSlots(restaurantId, null, Date.valueOf(bookingDate));
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ---- Agent / MCP entry point -------------------------------------------------------------

  @InvocableMethod(
    label='Get Restaurant Availability'
    description='Returns the available time slots of a restaurant for a given date'
  )
  global static List<AvailabilityResponse> getAvailability(List<AvailabilityRequest> requests) {
    List<AvailabilityResponse> responses = new List<AvailabilityResponse>();
    for (AvailabilityRequest request : requests) {
      AvailabilityResponse response = new AvailabilityResponse();
      try {
        Id restaurantId = String.isBlank(request.restaurantId) ? null : Id.valueOf(request.restaurantId);
        response.availability = getAvailableSlots(restaurantId, request.restaurantName, Date.valueOf(request.bookingDate));
        response.message = response.availability.hasSlots
          ? response.availability.slots.size() +
            ' available time slot(s) at ' +
            response.availability.restaurantName +
            ' on ' +
            response.availability.bookingDateLabel +
            '.'
          : 'No availability at ' + response.availability.restaurantName + ' on ' + response.availability.bookingDateLabel + '.';
      } catch (Exception e) {
        response.message = 'Could not check availability: ' + e.getMessage();
      }
      responses.add(response);
    }
    return responses;
  }

  global class AvailabilityRequest {
    @InvocableVariable(
      label='Restaurant Id'
      description='Salesforce Id of the restaurant, when known (included in the "Book a table at ..." messages). Either the Id or the name is required.'
    )
    global String restaurantId;

    @InvocableVariable(label='Restaurant Name' description='Name of the restaurant, when the Id is not known. Either the Id or the name is required.')
    global String restaurantName;

    @InvocableVariable(
      label='Date'
      description='Calendar date to check, in YYYY-MM-DD format. Deduce it from the conversation (today, tomorrow, January 3rd...) and ask the user if it is missing.'
      required=true
    )
    global String bookingDate;
  }

  global class AvailabilityResponse {
    @InvocableVariable(label='Availability' description='Restaurant, date and the list of available time slots')
    global Availability availability;

    @InvocableVariable(label='Message' description='Human-readable summary, or the error if the restaurant or the date could not be resolved')
    global String message;
  }
}
