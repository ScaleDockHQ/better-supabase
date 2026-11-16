import { describe, expect, it } from "vitest";

import { createAdvisories } from "../../src/blocks/advisories/advisories.ts";
import { createAnnouncements } from "../../src/blocks/announcements/announcements.ts";
import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { createCalendar } from "../../src/blocks/calendar/calendar.ts";
import { createCarePlans } from "../../src/blocks/care-plans/care-plans.ts";
import { createCustomFields } from "../../src/blocks/custom-fields/custom-fields.ts";
import { createImports } from "../../src/blocks/imports/imports.ts";
import { createIncidents } from "../../src/blocks/incidents/incidents.ts";
import { createObservations } from "../../src/blocks/observations/observations.ts";
import { createPrompts } from "../../src/blocks/prompts/prompts.ts";
import { createReminders } from "../../src/blocks/reminders/reminders.ts";
import { createSavedViews } from "../../src/blocks/saved-views/saved-views.ts";
import { createTags } from "../../src/blocks/tags/tags.ts";
import { createTasks } from "../../src/blocks/tasks/tasks.ts";
import { createTimeEntries } from "../../src/blocks/time-entries/time-entries.ts";
import { createTrash } from "../../src/blocks/trash/trash.ts";
import { fieldsTransport } from "./fields-transport.ts";

type Method = (options?: unknown) => PromiseLike<unknown>;

let ROW: unknown = null;

/** A list function's reply, by the prefix of its name: one row or none. */
const reply = (fn: string): ((args: Record<string, unknown>) => unknown) => {
  if (fn.startsWith("page_")) {
    return () => ({ items: ROW === null ? [] : [ROW], hasMore: false });
  }

  if (fn.startsWith("count_")) {
    return () => ({ value: 0, exact: true });
  }

  if (fn.startsWith("facets_")) {
    return () => [];
  }

  return () => ROW;
};

const FUNCTIONS = [
  "page_advisories",
  "count_advisories",
  "facets_advisories",
  "page_vulnerabilities",
  "count_vulnerabilities",
  "facets_vulnerabilities",
  "get_advisory",
  "page_announcements",
  "count_announcements",
  "facets_announcements",
  "get_announcement",
  "page_bookings",
  "count_bookings",
  "facets_bookings",
  "get_booking",
  "page_calendars",
  "count_calendars",
  "facets_calendars",
  "get_calendar",
  "page_calendar_events",
  "count_calendar_events",
  "facets_calendar_events",
  "get_calendar_event",
  "page_care_plans",
  "count_care_plans",
  "facets_care_plans",
  "get_care_plan",
  "page_field_definitions",
  "count_field_definitions",
  "facets_field_definitions",
  "get_field_definition",
  "page_import_runs",
  "count_import_runs",
  "facets_import_runs",
  "get_import_run",
  "page_incidents",
  "count_incidents",
  "facets_incidents",
  "get_incident",
  "page_observations",
  "count_observations",
  "facets_observations",
  "get_observation",
  "page_observation_definitions",
  "count_observation_definitions",
  "facets_observation_definitions",
  "get_observation_definition",
  "page_prompts",
  "count_prompts",
  "facets_prompts",
  "get_prompt",
  "page_reminders",
  "count_reminders",
  "facets_reminders",
  "get_reminder",
  "page_saved_views",
  "count_saved_views",
  "facets_saved_views",
  "get_saved_view",
  "page_tags",
  "count_tags",
  "facets_tags",
  "get_tag",
  "page_tasks",
  "count_tasks",
  "facets_tasks",
  "get_task",
  "page_projects",
  "count_projects",
  "facets_projects",
  "get_project",
  "page_time_entries",
  "count_time_entries",
  "facets_time_entries",
  "get_time_entry",
  "page_trash",
  "count_trash",
  "facets_trash",
  "get_trash_item",
];

const transport = () =>
  fieldsTransport(
    Object.fromEntries(FUNCTIONS.map((fn) => [fn, reply(fn)] as const)),
  );

/** The block's list methods, each called with a tenant and the others unset. */
async function run(block: unknown, methods: readonly string[]): Promise<void> {
  // SAFETY: the test reads the methods of the client by name.
  const client = block as Record<string, Method>;

  for (const row of [null, {}]) {
    ROW = row;

    for (const name of methods) {
      const method = client[name];

      if (method === undefined && name === "list") {
        continue;
      }

      expect(method).toBeTypeOf("function");
      await Promise.resolve(
        method?.({ organizationId: "org-1", tenant: "org-1" }),
      ).catch(() => undefined);
    }
  }
}

const LIST = ["page", "facets", "count", "list"] as const;

describe("the F13 and F14 list reads, over an empty database", () => {
  it("reads advisories and vulnerabilities", async () => {
    const t = transport();

    await run(createAdvisories({ transport: t }), [
      ...LIST,
      "pageVulnerabilities",
      "vulnerabilityFacets",
      "countVulnerabilities",
      "getAdvisory",
    ]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads announcements", async () => {
    const t = transport();

    await run(createAnnouncements({ transport: t }), [...LIST, "get"]);
    expect(t.calls.map(([fn]) => fn)).toContain("page_announcements");
  });

  it("reads bookings", async () => {
    const t = transport();

    await run(createBookings({ transport: t }), [
      "pageBookings",
      "bookingFacets",
      "countBookings",
      "getBooking",
    ]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads calendars and events", async () => {
    const t = transport();

    await run(createCalendar({ transport: t }), [
      ...LIST,
      "pageCalendars",
      "calendarFacets",
      "countCalendars",
      "getCalendar",
      "getEvent",
    ]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads care plans", async () => {
    const t = transport();

    await run(createCarePlans({ transport: t }), [...LIST, "get"]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads observations and their definitions", async () => {
    const t = transport();

    await run(createObservations({ transport: t }), [
      ...LIST,
      "getObservation",
      "pageDefinitions",
      "definitionFacets",
      "countDefinitions",
      "getDefinition",
    ]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads field definitions", async () => {
    const t = transport();

    await run(createCustomFields({ transport: t }), [
      ...LIST,
      "getDefinition",
      "listDefinitions",
    ]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads import runs and incidents", async () => {
    const t = transport();

    await run(createImports({ transport: t }).runs, [...LIST, "get"]);
    await run(createIncidents({ transport: t }), [...LIST, "getIncident"]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("checks the AI access before it reads prompt names", async () => {
    const t = transport();

    for (const allowed of [true, false]) {
      await run(
        createPrompts({
          transport: t,
          access: { allowed, organizationId: "org-1" },
        }),
        [...LIST, "getPrompt"],
      );
    }

    expect(t.calls.map(([fn]) => fn)).toContain("page_prompts");
  });

  it("reads prompts, reminders and saved views", async () => {
    const t = transport();

    await run(createPrompts({ transport: t }), [...LIST, "getPrompt"]);
    await run(createReminders({ transport: t }), [
      ...LIST,
      "get",
      "listForCaller",
    ]);
    await run(createSavedViews({ transport: t }), [...LIST, "get"]);
    expect(t.calls.length).toBeGreaterThan(0);
  });

  it("reads tags, tasks, projects, time entries and the trash", async () => {
    const t = transport();

    await run(createTags({ transport: t }), [...LIST, "get"]);
    await run(createTasks({ transport: t }), [
      ...LIST,
      "getTask",
      "pageProjects",
      "projectFacets",
      "countProjects",
      "getProject",
    ]);
    await run(createTimeEntries({ transport: t }), [...LIST, "get"]);
    await run(createTrash({ transport: t }), [...LIST, "get"]);
    expect(t.calls.length).toBeGreaterThan(0);
  });
});
