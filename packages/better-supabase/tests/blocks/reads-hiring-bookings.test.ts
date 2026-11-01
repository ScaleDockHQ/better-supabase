import { describe, expect, it } from "vitest";

import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { createHiring } from "../../src/blocks/hiring/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const application = (id: string, stage: string | null, state = "active") => ({
  id,
  job_id: "j1",
  candidate_type: "person",
  candidate_id: id,
  stage_id: stage,
  state,
  created_at: AT,
});

const job = (id: string, status: string) => ({
  id,
  title: id,
  status,
  fields: {},
});

describe("hiring reads", () => {
  it("jobs sends the organization and the status", async () => {
    const t = fieldsTransport({
      list_jobs: () => [job("j1", "open"), job("j2", "open")],
    });

    const jobs = await createHiring({ transport: t })
      .jobs({ organizationId: "o", status: "open" })
      .orThrow();

    expect(jobs.map((j) => j.id)).toEqual(["j1", "j2"]);
    expect(t.calls[0]).toEqual(["list_jobs", { tenant: "o", status: "open" }]);
  });

  it("applications keeps the board order the database gives", async () => {
    const t = fieldsTransport({
      list_applications: () => [
        application("a1", "s1"),
        application("a2", "s2"),
      ],
    });

    const applications = await createHiring({ transport: t })
      .applications({ jobId: "j1" })
      .orThrow();

    expect(applications.map((a) => a.id)).toEqual(["a1", "a2"]);
    expect(t.calls[0]?.[1]).toEqual({ job: "j1", state: null });
  });

  it("pipeline groups the applications by stage", async () => {
    const t = fieldsTransport({
      list_applications: () => [
        application("a1", "s1"),
        application("a2", "s1"),
        application("a3", null),
      ],
    });

    const stages = await createHiring({ transport: t })
      .pipeline({ jobId: "j1" })
      .orThrow();

    expect(
      stages.map((s) => [s.stageId, s.applications.map((a) => a.id)]),
    ).toEqual([
      ["s1", ["a1", "a2"]],
      [undefined, ["a3"]],
    ]);
  });

  it("close saves the job as closed", async () => {
    const t = fieldsTransport({ save_job: () => job("j1", "closed") });

    const closed = await createHiring({ transport: t })
      .close({ organizationId: "o", jobId: "j1" })
      .orThrow();

    expect(closed.status).toBe("closed");
    expect(t.calls[0]?.[1]).toMatchObject({ attrs: { status: "closed" } });
  });
});

describe("bookings reads", () => {
  it("resources and services read the lists", async () => {
    const t = fieldsTransport({
      list_booking_resources: () => [
        {
          id: "r1",
          name: "Studio",
          kind: "room",
          capacity: 2,
          tz: "UTC",
          active: true,
          calendarId: null,
          hostUserId: null,
        },
      ],
      list_booking_services: () => [
        {
          id: "s1",
          name: "Class",
          duration: "01:00:00",
          bufferBefore: "00:00:00",
          bufferAfter: "00:00:00",
          resourceKinds: ["room"],
          active: true,
        },
      ],
    });

    const bookings = createBookings({ transport: t });

    const resources = await bookings
      .resources({ organizationId: "o", includeInactive: true })
      .orThrow();

    const services = await bookings.services({ organizationId: "o" }).orThrow();

    expect(resources[0]).toMatchObject({ id: "r1", capacity: 2, active: true });
    expect(services[0]?.name).toBe("Class");
    expect(services[0]?.resourceKinds).toEqual(["room"]);
    expect(t.calls.map(([, args]) => args)).toEqual([
      { tenant: "o", include_inactive: true },
      { tenant: "o", include_inactive: false },
    ]);
  });
});
