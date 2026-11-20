import { defineScenarios } from "../src/scenarios.ts";

defineScenarios("eve dev, poll delivery, transaction connection", {
  command: "dev",
  delivery: "poll",
  connection: "transaction",
});
