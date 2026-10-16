import { api, wire } from "lwc";
import LightningModal from "lightning/modal";
import { getRecord } from "lightning/uiRecordApi";
import { execute } from "lightning/accApi";
import getBotId from "@salesforce/apex/AgentforcePanelController.getBotId";
import bookFromComponent from "@salesforce/apex/BookRestaurantService.bookFromComponent";
import NAME_FIELD from "@salesforce/schema/Restaurant__c.Name";

// API name of the agent that renders this component. accApi.execute() requires the
// BotDefinition Id of the target agent: nothing in the lightning__AgentforceOutput
// contract tells the component which agent rendered it, and calling execute() without
// a botId makes the panel fail ("Something went wrong. Refresh and try again.").
// The Id is resolved at runtime from this name so no org-specific Id lives in the code.
const AGENT_API_NAME = "Restaurant_Agent";

// Demo: three ways of booking, to show what the agent knows (or not) afterwards.
//  - lwc:       the component books (Apex insert). The agent is never told.
//  - lwcNotify: the component books, then tells the agent in natural language. The agent
//               receives it as a user utterance, not as a system event.
//  - agent:     the component only asks the agent, which runs its own booking action.
//               Same mechanism as the HXL widget's action/sendMessage.
const MODES = [
  { value: "lwc", label: "Book here (LWC)", buttonLabel: "Book here" },
  { value: "lwcNotify", label: "Book here and tell the agent", buttonLabel: "Book and tell the agent" },
  { value: "agent", label: "Ask the agent to book", buttonLabel: "Ask the agent" }
];
const DEFAULT_MODE = "agent";
const STORAGE_KEY = "restaurantBookingModal.mode";

export default class RestaurantBookingModal extends LightningModal {
  @api recordId;
  restaurantName;
  selectedSlot;
  errorMessage;
  isSending = false;
  mode = DEFAULT_MODE;

  connectedCallback() {
    this.mode = this.readStoredMode() || DEFAULT_MODE;
  }

  @wire(getRecord, { recordId: "$recordId", fields: [NAME_FIELD] })
  wiredRecord({ error, data }) {
    if (data) {
      this.restaurantName = data.fields?.Name?.value;
    } else if (error) {
      console.error(error);
    }
  }

  get headerLabel() {
    return this.restaurantName || "Book a table";
  }

  get buttonDisabled() {
    return !this.selectedSlot || this.isSending;
  }

  get bookLabel() {
    return MODES.find((m) => m.value === this.mode).buttonLabel;
  }

  get modeOptions() {
    return MODES.map((m) => ({ ...m, checked: m.value === this.mode }));
  }

  handleSelection(event) {
    this.selectedSlot = event.detail;
    this.errorMessage = undefined;
  }

  handleModeSelect(event) {
    this.mode = event.detail.value;
    this.errorMessage = undefined;
    this.storeMode(this.mode);
  }

  async handleBook() {
    this.isSending = true;
    this.errorMessage = undefined;
    try {
      let result;
      if (this.mode === "lwc") {
        result = await this.bookHere();
      } else if (this.mode === "lwcNotify") {
        result = await this.bookHere();
        this.tellAgent(
          `FYI, I just booked a table at ${result.restaurantName} myself (reference ${result.bookingReference}, ${this.selectedSlot.date} at ${this.selectedSlot.time}). Do not book again, just acknowledge.`
        );
      } else {
        const utterance = `Book a table at ${this.restaurantName} (restaurant Id ${this.recordId}) on ${this.selectedSlot.date} at ${this.selectedSlot.time}`;
        this.tellAgent(utterance);
        result = { message: utterance };
      }
      this.close({ mode: this.mode, ...result, date: this.selectedSlot.date, time: this.selectedSlot.time });
    } catch (error) {
      console.error("Booking failed", { mode: this.mode, error });
      this.errorMessage = `Booking failed (${this.mode}): ${error?.body?.message || error?.message || JSON.stringify(error)}`;
    } finally {
      this.isSending = false;
    }
  }

  bookHere() {
    return bookFromComponent({
      restaurantId: this.recordId,
      bookingDate: this.selectedSlot.date,
      bookingTime: this.selectedSlot.time
    });
  }

  // Fire and forget: the execute() promise only resolves once the panel has processed the
  // utterance (requests are queued and run in sequence), i.e. after the agent has answered.
  // Awaiting it kept the modal open for the whole agent turn.
  tellAgent(utterance) {
    getBotId({ developerName: AGENT_API_NAME })
      .then((botId) => {
        if (!botId) {
          throw new Error(`No BotDefinition found for ${AGENT_API_NAME}`);
        }
        return execute(utterance, botId);
      })
      .catch((error) => console.error("accApi.execute failed", { utterance, error }));
  }

  handleCancel() {
    this.close();
  }

  // sessionStorage is available under Lightning Web Security (isolated per namespace);
  // guarded anyway so the modal still works if storage is blocked.
  readStoredMode() {
    try {
      const stored = sessionStorage.getItem(STORAGE_KEY);
      return MODES.some((m) => m.value === stored) ? stored : undefined;
    } catch (e) {
      return undefined;
    }
  }

  storeMode(mode) {
    try {
      sessionStorage.setItem(STORAGE_KEY, mode);
    } catch (e) {
      // ignore: storage unavailable
    }
  }
}
