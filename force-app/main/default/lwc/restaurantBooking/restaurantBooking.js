import { LightningElement, api } from "lwc";
import LOCALE from "@salesforce/i18n/locale";

export default class RestaurantBooking extends LightningElement {
  @api recordId;
  dateDisplayed = new Date();

  get availableTimes() {
    return ["10:00", "10:30", "11:00", "11:30", "12:00", "12:30", "13:00", "13:30", "14:00"];
  }

  get dateDisplayedLabel() {
    return new Intl.DateTimeFormat(LOCALE).format(this.dateDisplayed);
  }

  handlePreviousDay() {
    const previousDate = new Date(this.dateDisplayed);
    previousDate.setDate(previousDate.getDate() - 1);
    this.dateDisplayed = previousDate;
  }

  handleNextDay() {
    const nextDate = new Date(this.dateDisplayed);
    nextDate.setDate(nextDate.getDate() + 1);
    this.dateDisplayed = nextDate;
  }

  handleRadioChange(event) {
    const selectedEvent = new CustomEvent("selected", { detail: event.target.value });

    // Dispatches the event.
    this.dispatchEvent(selectedEvent);
  }
}