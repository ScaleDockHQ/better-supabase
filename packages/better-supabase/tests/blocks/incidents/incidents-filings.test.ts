import { describe, expect, it } from "vitest";

import { createIncidents } from "../../../src/blocks/incidents/index.ts";

const AT = "2026-10-22T10:00:00Z";

const FILING = {
  id: "f1",
  incidentId: "i1",
  regime: "nis2",
  stage: "early_warning",
};

const FULL_FILING = {
  ...FILING,
  dueAt: AT,
  submittedAt: AT,
  submittedBy: "u1",
  reference: "REF-1",
  notes: "Sent",
};

const PROFILE = {
  incidentId: "i1",
  regimes: ["nis2", "dora"],
  awareAt: AT,
  significant: true,
  activelyExploited: true,
  classification: "major",
  classifiedAt: AT,
  measureAvailableAt: AT,
  filings: [FULL_FILING, FILING],
};

const ACTION = {
  id: "a1",
  postmortemId: "p1",
  taskId: "t1",
  title: "Fix",
  state: "open",
};

const POSTMORTEM = {
  id: "p1",
  incidentId: "i1",
  status: "published",
  summary: "S",
  impact: "I",
  rootCause: "R",
  resolution: "Z",
  publishedAt: AT,
  authorId: "u1",
  createdAt: AT,
  updatedAt: AT,
  actions: [{ ...ACTION, dueAt: AT, closedAt: AT, createdAt: AT }, ACTION],
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createIncidents regulatory filings", () => {
  it("saves and reads the regulatory profile", async () => {
    const fake = fakeTransport({
      save_incident_regulatory_profile: PROFILE,
      get_incident_regulatory_profile: {
        incidentId: "i1",
        awareAt: AT,
        regimes: "none",
      },
    });

    const incidents = createIncidents({ transport: fake.transport });

    const saved = await incidents
      .saveRegulatoryProfile({
        incidentId: "i1",
        input: {
          regimes: ["nis2", "dora"],
          awareAt: Temporal.Instant.from(AT),
          classification: "major",
          classifiedAt: Temporal.Instant.from(AT),
          significant: true,
          activelyExploited: true,
          measureAvailableAt: Temporal.Instant.from(AT),
        },
      })
      .orThrow();

    expect(saved).toMatchObject({
      regimes: ["nis2", "dora"],
      significant: true,
      activelyExploited: true,
      classification: "major",
    });
    expect(saved.classifiedAt?.toString()).toBe(AT);
    expect(saved.measureAvailableAt?.toString()).toBe(AT);
    expect(saved.filings[0]).toMatchObject({
      reference: "REF-1",
      notes: "Sent",
      submittedBy: "u1",
    });
    expect(saved.filings[1]?.dueAt).toBeUndefined();

    expect(fake.calls[0]).toEqual([
      "save_incident_regulatory_profile",
      {
        incident_id: "i1",
        attrs: {
          regimes: ["nis2", "dora"],
          awareAt: AT,
          classification: "major",
          classifiedAt: AT,
          significant: true,
          activelyExploited: true,
          measureAvailableAt: AT,
        },
      },
    ]);

    await incidents
      .saveRegulatoryProfile({
        incidentId: "i1",
        input: {
          classification: null,
          classifiedAt: null,
          measureAvailableAt: null,
        },
      })
      .orThrow();

    expect(fake.calls[1]?.[1]).toEqual({
      incident_id: "i1",
      attrs: {
        classification: null,
        classifiedAt: null,
        measureAvailableAt: null,
      },
    });

    await incidents
      .saveRegulatoryProfile({ incidentId: "i1", input: {} })
      .orThrow();
    expect(fake.calls[2]?.[1]).toEqual({ incident_id: "i1", attrs: {} });

    const bare = await incidents.regulatoryProfile("i1").orThrow();

    expect(bare).toMatchObject({
      regimes: [],
      significant: false,
      activelyExploited: false,
      filings: [],
    });
    expect(bare?.classification).toBeUndefined();
  });

  it("reads a missing regulatory profile as undefined", async () => {
    const incidents = createIncidents({
      transport: fakeTransport({ get_incident_regulatory_profile: null })
        .transport,
    });

    expect(await incidents.regulatoryProfile("i1").orThrow()).toBeUndefined();
  });

  it("lists and submits filings", async () => {
    const fake = fakeTransport({
      list_incident_filings: [FULL_FILING, FILING],
      submit_incident_filing: FULL_FILING,
    });

    const incidents = createIncidents({ transport: fake.transport });

    const listed = await incidents
      .filings({ organizationId: "org-1" })
      .orThrow();

    expect(listed).toHaveLength(2);
    expect(listed[0]?.dueAt?.toString()).toBe(AT);
    await incidents
      .filings({ organizationId: "org-1", pending: false })
      .orThrow();

    const filed = await incidents
      .submitFiling({
        incidentId: "i1",
        regime: "nis2",
        stage: "notification",
        input: {
          reference: "REF-1",
          notes: "Sent",
          submittedAt: Temporal.Instant.from(AT),
        },
      })
      .orThrow();

    expect(filed.reference).toBe("REF-1");
    await incidents
      .submitFiling({ incidentId: "i1", regime: "cra", stage: "final" })
      .orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      { tenant: "org-1", pending: true },
      { tenant: "org-1", pending: false },
      {
        incident_id: "i1",
        regime: "nis2",
        stage: "notification",
        reference: "REF-1",
        notes: "Sent",
        submitted_at: AT,
      },
      {
        incident_id: "i1",
        regime: "cra",
        stage: "final",
        reference: null,
        notes: null,
        submitted_at: null,
      },
    ]);
  });

  it("rejects malformed filing and profile rows", async () => {
    const incidents = createIncidents({
      transport: fakeTransport({
        submit_incident_filing: { ...FILING, regime: "sox" },
        list_incident_filings: [{ ...FILING, stage: "late" }],
        save_incident_regulatory_profile: { ...PROFILE, regimes: ["x"] },
        get_incident_regulatory_profile: { ...PROFILE, classification: "huge" },
      }).transport,
    });

    expect(
      (
        await incidents.submitFiling({
          incidentId: "i1",
          regime: "nis2",
          stage: "final",
        })
      ).ok,
    ).toBe(false);
    expect((await incidents.filings({ organizationId: "org-1" })).ok).toBe(
      false,
    );
    expect(
      (await incidents.saveRegulatoryProfile({ incidentId: "i1", input: {} }))
        .ok,
    ).toBe(false);
    expect((await incidents.regulatoryProfile("i1")).ok).toBe(false);
  });
});

describe("createIncidents postmortems and public pages", () => {
  it("saves, publishes and edits postmortem actions", async () => {
    const fake = fakeTransport({
      save_incident_postmortem: POSTMORTEM,
      publish_incident_postmortem: POSTMORTEM,
      add_incident_postmortem_action: { ...ACTION, dueAt: AT },
      remove_incident_postmortem_action: { ...POSTMORTEM, actions: null },
    });

    const incidents = createIncidents({ transport: fake.transport });

    const saved = await incidents
      .savePostmortem({
        incidentId: "i1",
        input: { summary: "S", impact: "I", rootCause: "R", resolution: "Z" },
      })
      .orThrow();

    expect(saved).toMatchObject({
      summary: "S",
      rootCause: "R",
      resolution: "Z",
      authorId: "u1",
    });
    expect(saved.actions[0]?.closedAt?.toString()).toBe(AT);
    expect(saved.actions[1]?.dueAt).toBeUndefined();
    expect((await incidents.publishPostmortem("i1").orThrow()).status).toBe(
      "published",
    );

    const added = await incidents
      .addPostmortemAction({
        postmortemId: "p1",
        input: {
          title: "Fix",
          assigneeId: "u2",
          dueAt: Temporal.Instant.from(AT),
        },
      })
      .orThrow();

    expect(added.dueAt?.toString()).toBe(AT);
    await incidents
      .addPostmortemAction({ postmortemId: "p1", input: { title: "Fix" } })
      .orThrow();

    const removed = await incidents.removePostmortemAction("a1").orThrow();

    expect(removed.actions).toEqual([]);
    expect(fake.calls[2]?.[1]).toEqual({
      postmortem_id: "p1",
      title: "Fix",
      assignee_id: "u2",
      due_at: AT,
    });
    expect(fake.calls[3]?.[1]).toEqual({
      postmortem_id: "p1",
      title: "Fix",
      assignee_id: null,
      due_at: null,
    });
  });

  it("rejects a postmortem with an unknown status", async () => {
    const incidents = createIncidents({
      transport: fakeTransport({
        save_incident_postmortem: { ...POSTMORTEM, status: "lost" },
      }).transport,
    });

    expect(
      (await incidents.savePostmortem({ incidentId: "i1", input: {} })).ok,
    ).toBe(false);
  });

  it("reads the public status page", async () => {
    const fake = fakeTransport({
      public_status_page: {
        slug: "acme",
        title: "Acme",
        description: "Status",
        days: 30,
        status: "degraded",
        components: [
          {
            id: "c1",
            name: "API",
            description: "REST",
            group: "Core",
            status: "degraded",
            uptimePercent: 99.5,
            uptime: [
              { date: "2026-10-21", status: "degraded", downMinutes: "12" },
            ],
          },
          { id: "c2", name: "Web", status: "operational" },
        ],
        incidents: [
          {
            id: "i1",
            title: "Errors",
            severity: "sev2",
            status: "resolved",
            startedAt: AT,
            resolvedAt: AT,
            components: [{ id: "c1", name: "API", impact: "degraded" }],
            updates: [{ status: "resolved", body: "Done", createdAt: AT }],
            postmortem: { summary: "Why", publishedAt: AT },
          },
          {
            id: "i2",
            title: "Slow",
            severity: "sev4",
            status: "investigating",
            startedAt: AT,
            postmortem: { publishedAt: AT },
          },
          {
            id: "i3",
            title: "Other",
            severity: "sev3",
            status: "monitoring",
            startedAt: AT,
            postmortem: "none",
          },
        ],
      },
    });

    const incidents = createIncidents({ transport: fake.transport });

    const page = await incidents
      .publicStatusPage({ slug: "acme", days: 30 })
      .orThrow();

    expect(page).toMatchObject({
      slug: "acme",
      days: 30,
      description: "Status",
    });
    expect(page?.components[0]).toMatchObject({
      group: "Core",
      uptimePercent: 99.5,
    });
    expect(page?.components[0]?.uptime[0]).toMatchObject({
      status: "degraded",
      downMinutes: 12,
    });
    expect(page?.components[1]).toMatchObject({
      uptimePercent: 100,
      uptime: [],
    });
    expect(page?.incidents[0]).toMatchObject({
      components: [{ id: "c1", impact: "degraded" }],
      postmortem: { summary: "Why" },
    });
    expect(page?.incidents[0]?.resolvedAt?.toString()).toBe(AT);
    expect(page?.incidents[1]?.postmortem?.summary).toBeUndefined();
    expect(page?.incidents[2]?.postmortem).toBeUndefined();
    expect(page?.incidents[1]?.components).toEqual([]);

    await incidents.publicStatusPage({ slug: "acme" }).orThrow();
    expect(fake.calls.map(([, args]) => args)).toEqual([
      { slug: "acme", days: 30 },
      { slug: "acme", days: null },
    ]);
  });

  it("reads a missing public page as undefined and rejects bad rows", async () => {
    const missing = createIncidents({
      transport: fakeTransport({ public_status_page: null }).transport,
    });

    expect(
      await missing.publicStatusPage({ slug: "none" }).orThrow(),
    ).toBeUndefined();

    const bad = createIncidents({
      transport: fakeTransport({
        public_status_page: {
          slug: "a",
          title: "A",
          days: 90,
          status: "broken",
        },
      }).transport,
    });

    expect((await bad.publicStatusPage({ slug: "a" })).ok).toBe(false);
  });
});
