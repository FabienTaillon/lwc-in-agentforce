import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { getRecords } from "lightning/uiRecordApi";
import RestaurantBookingModal from "c/restaurantBookingModal";
import RESTAURANT_OBJECT from "@salesforce/schema/Restaurant__c";
import ID_FIELD from "@salesforce/schema/Restaurant__c.Id";
import NAME_FIELD from "@salesforce/schema/Restaurant__c.Name";
import NUMBER_OF_STARS_FIELD from "@salesforce/schema/Restaurant__c.NumberOfStars__c";
import TYPE_OF_CUISINE_FIELD from "@salesforce/schema/Restaurant__c.TypeOfCuisine__c";
import PRICE_RANGE_FIELD from "@salesforce/schema/Restaurant__c.PriceRange__c";

export default class RestaurantDetails extends NavigationMixin(LightningElement) {
  @api value;

  @wire(getObjectInfo, { objectApiName: RESTAURANT_OBJECT })
  wiredObjectInfo({ error, data }) {
    if (data) {
      this.typeOfCuisineLabel = data.fields.TypeOfCuisine__c.label;
      this.priceRangeLabel = data.fields.PriceRange__c.label;
    } else if (error) {
      console.log(error);
    }
  }

  @wire(getRecords, {
    records: "$recordInputs"
  })
  wiredRestaurants({ error, data }) {
    if (data) {
      this.restaurantsData = data.results.map((restaurant) => {
        return {
          id: restaurant.result.fields.Id.value,
          name: restaurant.result.fields.Name.value,
          stars: restaurant.result.fields.NumberOfStars__c.value,
          cuisine: restaurant.result.fields.TypeOfCuisine__c.value?.replace(";", ", "),
          price: restaurant.result.fields.PriceRange__c.value,
          link: `/${restaurant.result.fields.Id.value}`
        };
      });
    } else if (error) {
      console.log(error);
    }
  }

  restaurantsData = [];
  recordIds;
  typeOfCuisineLabel = "";
  priceRangeLabel = "";

  get recordInputs() {
    return [
      {
        recordIds: this.recordIds,
        fields: [ID_FIELD, NAME_FIELD, NUMBER_OF_STARS_FIELD, TYPE_OF_CUISINE_FIELD, PRICE_RANGE_FIELD]
      }
    ];
  }

  connectedCallback() {
    if (this.value) {
      this.recordIds = this.value.listRestaurants?.map((obj) => obj.id);
    }
  }

  handleNavigation(event) {
    event.preventDefault();

    const restaurantId = event.target.dataset.restaurantId;
    const restaurant = this.restaurantsData.find((element) => element.id === restaurantId);

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: restaurant.id,
        actionName: "view"
      }
    });
  }

  async handleBooking(event) {
    const restaurantId = event.target.dataset.restaurantId;
    // const restaurant = this.restaurantsData.find((element) => element.id === restaurantId);

    const bookingResult = await RestaurantBookingModal.open({
      // it is set on lightning-modal-header instead
      recordId: restaurantId
    });

    // Demo modes (see restaurantBookingModal): "lwc" books silently, "lwcNotify" books then
    // tells the agent, "agent" only asks the agent to book. In "agent" mode the request shows up
    // in the conversation itself, so no toast; in the two "lwc" modes the toast is the only
    // feedback on the booking created by the component.
    if (bookingResult && bookingResult.mode !== "agent") {
      const titles = {
        lwc: "Booked by the component, the agent does not know",
        lwcNotify: "Booked by the component, the agent was told"
      };
      const url = await this[NavigationMixin.GenerateUrl]({
        type: "standard__recordPage",
        attributes: { recordId: bookingResult.bookingId, actionName: "view" }
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: titles[bookingResult.mode] || "Booking",
          message: `Table booked at ${bookingResult.restaurantName} on ${bookingResult.date} at ${bookingResult.time}: {0}`,
          messageData: [{ url, label: bookingResult.bookingReference }],
          variant: "success"
        })
      );
    }
  }
}