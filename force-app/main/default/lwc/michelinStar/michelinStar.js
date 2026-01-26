import { LightningElement, api, wire } from "lwc";
import { getRecord } from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import RESTAURANT_OBJECT from "@salesforce/schema/Restaurant__c";
import NUMBER_OF_STARS_FIELD from "@salesforce/schema/Restaurant__c.NumberOfStars__c";

export default class MichelinStar extends LightningElement {
  @api recordId;

  numberOfStars;
  numberOfStarsLabel;

  @wire(getObjectInfo, { objectApiName: RESTAURANT_OBJECT })
  wiredObjectInfo({ error, data }) {
    if (data) {
      this.numberOfStarsLabel = data.fields.NumberOfStars__c.label;
    } else if (error) {
      console.log(error);
    }
  }

  @wire(getRecord, { recordId: "$recordId", fields: [NUMBER_OF_STARS_FIELD] })
  wiredRecord({ error, data }) {
    if (data) {
      this.numberOfStars = data.fields?.NumberOfStars__c?.value;
    } else if (error) {
      console.log(error);
    }
  }
}