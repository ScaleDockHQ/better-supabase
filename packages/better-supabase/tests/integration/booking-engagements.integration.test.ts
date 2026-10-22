import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createActivities } from "../../src/blocks/activities/index.ts";
import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "bookings",
  "contacts",
  "activities",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
  modules: { activities: { options: { bookings: true } } },
};

describe.skipIf(!live)("bookings to engagements", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("logs a confirmed booking as a meeting on the booker's contact", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const bookings = createBookings({ transport });
      const parties = createContacts({ transport });
      const engagements = createActivities({ transport });

      await s.as(owner);

      const resource = await bookings
        .saveResource(org, { name: "Ann", kind: "staff", tz: "UTC" })
        .orThrow();

      await bookings
        .setAvailability(resource.id, [
          { weekday: 1, start: "09:00", end: "12:00" },
        ])
        .orThrow();

      const service = await bookings
        .saveService(org, {
          name: "Demo",
          duration: Temporal.Duration.from({ minutes: 30 }),
          resourceKinds: ["staff"],
        })
        .orThrow();

      const acme = await parties.saveCompany(org, { name: "Acme" }).orThrow();

      const ada = await parties
        .savePerson(org, { name: "Ada", email: "ada@acme.test" })
        .orThrow();

      await parties.linkPerson(acme.id, ada.id, { primary: true }).orThrow();
      const person = { type: "person", id: ada.id };

      await s.as(member);

      const held = await bookings
        .hold(
          service.id,
          resource.id,
          Temporal.Instant.from("2030-03-04T09:00:00Z"),
          { name: "Ada", email: "ADA@acme.test", notes: "Wants the API tour" },
        )
        .orThrow();

      await s.as(owner);
      expect(await engagements.of(person).orThrow()).toEqual([]);

      await s.as(member);
      await bookings.confirm(held.id).orThrow();

      await s.as(owner);
      const [meeting] = await engagements.of(person).orThrow();

      expect(meeting).toMatchObject({
        type: "meeting",
        title: "Demo with Ada",
        body: "Wants the API tour",
        externalRef: `booking:${held.id}`,
        durationSeconds: 1800,
        subjects: [person, { type: "company", id: acme.id }],
      });
      expect(meeting?.dueAt?.toString()).toBe("2030-03-04T09:00:00Z");
      expect(meeting?.doneAt).toBeUndefined();

      await s.as(member);
      await bookings.cancel(held.id, "double booked").orThrow();

      await s.as(owner);

      const [cancelled] = await engagements
        .of({ type: "company", id: acme.id })
        .orThrow();

      expect(cancelled?.id).toBe(meeting?.id);
      expect(cancelled?.outcome).toBe("cancelled: double booked");
      expect(cancelled?.doneAt).toBeDefined();

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'engagement.%' order by position",
      );

      expect(events.map((event) => event.type)).toEqual([
        "engagement.logged",
        "engagement.completed",
      ]);
    } finally {
      await s.close();
    }
  });
});
