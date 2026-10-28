import { LightningElement, api } from "lwc";
import LOCALE from "@salesforce/i18n/locale";
import getSlots from "@salesforce/apex/RestaurantAvailabilityService.getSlots";

export default class RestaurantBooking extends LightningElement {
  @api recordId;
  dateDisplayed = new Date();
  selectedTime;
  availableTimes = [];
  isLoading = false;
  errorMessage;

  connectedCallback() {
    this.loadSlots();
  }

  get dateDisplayedLabel() {
    return new Intl.DateTimeFormat(LOCALE, { dateStyle: "full" }).format(this.dateDisplayed);
  }

  // ISO calendar date (YYYY-MM-DD) in the browser's local time zone
  get dateDisplayedIso() {
    const pad = (n) => String(n).padStart(2, "0");
    const d = this.dateDisplayed;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  get hasSlots() {
    return !this.isLoading && !this.errorMessage && this.availableTimes.length > 0;
  }

  get hasNoSlots() {
    return !this.isLoading && !this.errorMessage && this.availableTimes.length === 0;
  }

  handlePreviousDay() {
    this.shiftDay(-1);
  }

  handleNextDay() {
    this.shiftDay(1);
  }

  shiftDay(days) {
    const date = new Date(this.dateDisplayed);
    date.setDate(date.getDate() + days);
    this.dateDisplayed = date;
    this.loadSlots();
  }

  // Same source of truth as the agent and the MCP tool: opening slots minus existing bookings.
  // Not cached on purpose (availability changes with every booking).
  async loadSlots() {
    this.isLoading = true;
    this.errorMessage = undefined;
    this.selectedTime = undefined;
    this.emitSelection();
    try {
      const availability = await getSlots({ restaurantId: this.recordId, bookingDate: this.dateDisplayedIso });
      this.availableTimes = (availability?.slots || []).map((slot) => slot.startTime);
    } catch (error) {
      this.availableTimes = [];
      this.errorMessage = error?.body?.message || error?.message || "Could not load availability";
    } finally {
      this.isLoading = false;
    }
  }

  handleRadioChange(event) {
    this.selectedTime = event.target.value;
    this.emitSelection();
  }

  // Emits { date: "YYYY-MM-DD", time: "HH:mm" }, or null when the selection is cleared
  // (day change reloads the slots), so the parent always holds the full selection state.
  emitSelection() {
    this.dispatchEvent(
      new CustomEvent("selected", {
        detail: this.selectedTime ? { date: this.dateDisplayedIso, time: this.selectedTime } : null
      })
    );
  }
}
