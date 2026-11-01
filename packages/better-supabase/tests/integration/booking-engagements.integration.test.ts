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
        .saveResource({
          organizationId: org,
          input: { name: "Ann", kind: "staff", tz: "UTC" },
        })
        .orThrow();

      await bookings
        .setAvailability({
          resourceId: resource.id,
          hours: [{ weekday: 1, start: "09:00", end: "12:00" }],
        })
        .orThrow();

      const service = await bookings
        .saveService({
          organizationId: org,
          input: {
            name: "Demo",
            duration: Temporal.Duration.from({ minutes: 30 }),
            resourceKinds: ["staff"],
          },
        })
        .orThrow();

      const acme = await parties
        .saveCompany({ organizationId: org, input: { name: "Acme" } })
        .orThrow();

      const ada = await parties
        .savePerson({
          organizationId: org,
          input: { name: "Ada", email: "ada@acme.test" },
        })
        .orThrow();

      await parties
        .linkPerson({
          companyId: acme.id,
          personId: ada.id,
          link: { primary: true },
        })
        .orThrow();
      const person = { type: "person", id: ada.id };

      await s.as(member);

      const held = await bookings
        .hold({
          serviceId: service.id,
          resourceId: resource.id,
          startsAt: Temporal.Instant.from("2030-03-04T09:00:00Z"),
          customer: {
            name: "Ada",
            email: "ADA@acme.test",
            notes: "Wants the API tour",
          },
        })
        .orThrow();

      await s.as(owner);
      expect(await engagements.of({ subject: person }).orThrow()).toEqual([]);

      await s.as(member);
      await bookings.confirm(held.id).orThrow();

      await s.as(owner);
      const [meeting] = await engagements.of({ subject: person }).orThrow();

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
      await bookings
        .cancel({ bookingId: held.id, reason: "double booked" })
        .orThrow();

      await s.as(owner);

      const [cancelled] = await engagements
        .of({ subject: { type: "company", id: acme.id } })
        .orThrow();

      expect(cancelled?.id).toBe(meeting?.id);
      expect(cancelled?.outcome).toBe("cancelled: double booked");
      expect(cancelled?.doneAt).toBeDefined();

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'activity.%' order by position",
      );

      expect(events.map((event) => event.type)).toEqual([
        "activity.logged",
        "activity.completed",
      ]);
    } finally {
      await s.close();
    }
  });
});
