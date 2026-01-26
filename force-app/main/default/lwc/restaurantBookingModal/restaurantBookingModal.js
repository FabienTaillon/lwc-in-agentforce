import { api, wire } from "lwc";
import LightningModal from "lightning/modal";
import { getRecord } from "lightning/uiRecordApi";
import NAME_FIELD from "@salesforce/schema/Restaurant__c.Name";

export default class RestaurantBookingModal extends LightningModal {
  @api recordId;
  restaurantName;
  selectedTimeSlot;

  @wire(getRecord, { recordId: "$recordId", fields: [NAME_FIELD] })
  wiredRecord({ error, data }) {
    if (data) {
      this.restaurantName = data.fields?.Name?.value;
    } else if (error) {
      console.log(error);
    }
  }

  get buttonDisabled() {
    return !this.selectedTimeSlot;
  }

  handleSelection(event) {
    console.log(event);
    console.log(event.detail);
    this.selectedTimeSlot = event.detail;
  }

  handleBook() {
    this.close("TEST");
  }

  handleCancel() {
    this.close();
  }
}