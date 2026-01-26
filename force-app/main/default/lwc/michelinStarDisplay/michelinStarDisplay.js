import { LightningElement, api } from "lwc";

export default class MichelinStarDisplay extends LightningElement {
  @api
  get numberOfStars() {
    return this.stars.length;
  }

  set numberOfStars(value) {
    this.stars = [];
    for (let i = 1; i <= value; i++) {
      this.stars.push(i);
    }
  }

  stars = [];

  get hasStars() {
    return this.stars.length > 0;
  }
}