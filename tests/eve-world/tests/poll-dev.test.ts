import { defineScenarios } from "../src/scenarios.ts";

defineScenarios("eve dev, poll delivery, session connection", {
  command: "dev",
  delivery: "poll",
});
