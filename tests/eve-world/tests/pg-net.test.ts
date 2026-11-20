import { defineScenarios } from "../src/scenarios.ts";

// Postgres calls the dev server back through `host.docker.internal`, so this runs on a machine
// with the local stack in Docker (CI included) and nowhere else.
defineScenarios("eve dev, pg_net delivery, session connection", {
  command: "dev",
  delivery: "pg_net",
});
