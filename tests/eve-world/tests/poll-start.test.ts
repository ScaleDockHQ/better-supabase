import { defineScenarios } from "../src/scenarios.ts";

defineScenarios("eve start (built), poll delivery, session connection", {
  command: "start",
  delivery: "poll",
});
