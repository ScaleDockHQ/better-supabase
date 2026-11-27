import { describe, expect, it } from "vitest";

import { createProjects } from "../../src/blocks/projects/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

const done = <T>(data: T): AsyncResult<T> =>
  new AsyncResult(Promise.resolve(ok(data)));

const failure = <T = never>(): AsyncResult<T> =>
  AsyncResult.err(dbError("not_found", "no"));

// SAFETY: the page reads only the methods these fakes define.
const asParts = <T>(value: object): T => value as T;

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

const project = {
  id: "p",
  health: "on_track" as const,
  startOn: day("2026-11-01"),
  targetOn: day("2026-11-20"),
};

function client(
  transport: {
    call: (
      schema: string,
      fn: string,
      args: Record<string, unknown>,
    ) => Promise<unknown>;
  },
  tasks: object,
  extra: object = {},
) {
  return createProjects(
    asParts({
      tenant: "org",
      transport,
      parts: {
        tasks,
        subjects: { members: { list: () => done([{ userId: "a" }]) } },
        relations: {
          of: () =>
            done([
              { direction: "in", subject: { type: "project", id: "late" } },
              { direction: "out", subject: { type: "project", id: "open" } },
            ]),
        },
        attachments: { counts: () => done({ p: 4, t1: 1 }) },
        timeline: { list: () => done([{ id: "e" }]) },
        "saved-views": { page: () => done({ items: [{ id: "v" }] }) },
        comments: { counts: () => done({ t1: 2 }) },
        tags: { forSubjects: () => done({ t1: ["bug"] }) },
        "time-entries": {
          list: () => done([]),
          approve: () => done({ id: "ts" }),
        },
        "billable-time": { invoice: () => done({ id: "inv" }) },
        ...extra,
      },
    }),
  );
}

const tasks = {
  getProject: (id: string) =>
    done(
      id === "open"
        ? { id }
        : {
            ...project,
            id,
            targetOn: id === "late" ? day("2026-12-01") : project.targetOn,
          },
    ),
  facets: () =>
    done([
      { facet: "state", values: [{ value: "started", count: { value: 2 } }] },
    ]),
  pageMilestones: () => done([{ id: "m" }]),
  getTask: (id: string) => done({ id, subtasks: { done: 1, total: 3 } }),
};

describe("project page", () => {
  const calls: [string, Record<string, unknown>][] = [];

  const transport = {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      if (fn === "page_project_updates") {
        const projectId = args["project"];

        if (projectId === "none") {
          return Promise.resolve("nope");
        }

        if (projectId === "empty") {
          return Promise.resolve([]);
        }

        if (projectId === "bad-id") {
          return Promise.resolve([1]);
        }

        if (projectId === "bad-fields") {
          return Promise.resolve([{ id: "u", health: 1, body: 1 }]);
        }

        if (projectId === "throws") {
          return Promise.reject(new Error("down"));
        }

        return Promise.resolve([
          { id: "u", health: "at_risk", body: "Slipping" },
          "skip",
        ]);
      }

      if (fn === "page_initiatives") {
        if (args["tenant"] === "nope") {
          return Promise.resolve({ id: "i" });
        }

        return Promise.resolve([{ id: "i" }, "skip"]);
      }

      if (fn === "link_initiative_project") {
        return Promise.resolve(args["initiative"] === "i");
      }

      if (fn === "save_project_update" && args["body"] === "") {
        return Promise.resolve(null);
      }

      if (fn === "save_initiative" && args["id"] === "bare") {
        return Promise.resolve(null);
      }

      return Promise.resolve({ id: "saved" });
    },
  };

  const projects = client(transport, tasks);

  it("gathers the overview, the cards and the saved views", async () => {
    const overview = await projects
      .overview({ organizationId: "org", projectId: "p" })
      .orThrow();

    expect(overview.health).toBe("on_track");
    expect(overview.tasks).toEqual({ started: 2 });
    expect(overview.files).toBe(4);
    expect(overview.blockedBy).toEqual([{ type: "project", id: "late" }]);
    expect(overview.blocking).toEqual([{ type: "project", id: "open" }]);
    expect(overview.update).toEqual({
      id: "u",
      health: "at_risk",
      body: "Slipping",
    });
    expect(overview.views).toEqual([{ id: "v" }]);

    expect(
      await projects.cards({ organizationId: "org", taskIds: [] }),
    ).toMatchObject({ ok: true, data: {} });

    const cards = await projects
      .cards({ organizationId: "org", taskIds: ["t1", "missing"] })
      .orThrow();

    expect(cards["t1"]).toEqual({
      comments: 2,
      tags: ["bug"],
      attachments: 1,
      subtasks: { done: 1, total: 3 },
    });
    expect(cards["missing"]?.comments).toBe(0);
    expect(cards["missing"]?.tags).toEqual([]);

    expect(await projects.views("p").orThrow()).toEqual([{ id: "v" }]);
  });

  it("marks a dependency violated when the blocker ends after the work starts", async () => {
    const rows = await projects.dependencies({ projectId: "p" }).orThrow();

    expect(rows).toEqual([
      { direction: "in", projectId: "late", violated: true },
      { direction: "out", projectId: "open", violated: false },
    ]);
  });

  it("saves an update, an initiative and a link", async () => {
    calls.length = 0;

    expect(
      await projects
        .postUpdate({
          organizationId: "org",
          projectId: "p",
          health: "at_risk",
          body: "Note",
        })
        .orThrow(),
    ).toEqual({ id: "saved" });
    expect(
      await projects
        .postUpdate({
          organizationId: "org",
          projectId: "p",
          health: "off_track",
          body: "",
        })
        .orThrow(),
    ).toEqual({});

    await projects
      .saveInitiative({ organizationId: "org", name: "Pay" })
      .orThrow();
    await projects
      .saveInitiative({
        organizationId: "org",
        initiativeId: "i",
        name: "Pay",
        description: "Cards",
        status: "active",
        priority: 2,
        ownerId: "a",
        targetOn: "2026-12-01",
        parentId: "parent",
      })
      .orThrow();

    const saved = calls.find(([fn]) => fn === "save_initiative");
    expect(saved?.[1]["attrs"]).toMatchObject({
      description: null,
      parentId: null,
    });

    expect(await projects.pageInitiatives("org").orThrow()).toEqual([
      { id: "i" },
    ]);
    expect(
      await projects
        .linkInitiative({ initiativeId: "i", projectId: "p" })
        .orThrow(),
    ).toBe(true);
    expect(
      await projects
        .linkInitiative({ initiativeId: "other", projectId: "p" })
        .orThrow(),
    ).toBe(false);
  });

  it("returns the first failed read", async () => {
    const broken = client(transport, { ...tasks, getProject: failure });
    expect(
      (await broken.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noFacets = client(transport, { ...tasks, facets: failure });
    expect(
      (await noFacets.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noComments = client(transport, tasks, {
      comments: { counts: failure },
    });

    expect(
      (await noComments.cards({ organizationId: "org", taskIds: ["t1"] })).ok,
    ).toBe(false);

    const noTask = client(transport, { ...tasks, getTask: failure });

    expect(
      (await noTask.cards({ organizationId: "org", taskIds: ["t1"] })).ok,
    ).toBe(false);

    const noLink = client(transport, tasks, { relations: { of: failure } });

    expect((await noLink.dependencies({ projectId: "p" })).ok).toBe(false);

    const noMembers = client(transport, tasks, {
      subjects: { members: { list: failure } },
    });

    expect(
      (await noMembers.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noLinks = client(transport, tasks, { relations: { of: failure } });

    expect(
      (await noLinks.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noFiles = client(transport, tasks, {
      attachments: { counts: failure },
    });

    expect(
      (await noFiles.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);
    expect(
      (await noFiles.cards({ organizationId: "org", taskIds: ["t1"] })).ok,
    ).toBe(false);

    const noActivity = client(transport, tasks, {
      timeline: { list: failure },
    });

    expect(
      (await noActivity.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noViews = client(transport, tasks, {
      "saved-views": { page: failure },
    });

    expect(
      (await noViews.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noMoney = client(transport, tasks, {
      "time-entries": { list: failure, approve: () => done({}) },
    });

    expect(
      (await noMoney.overview({ organizationId: "org", projectId: "p" })).ok,
    ).toBe(false);

    const noMilestones = client(transport, {
      ...tasks,
      pageMilestones: failure,
    });

    expect(
      (await noMilestones.overview({ organizationId: "org", projectId: "p" }))
        .ok,
    ).toBe(false);

    expect(
      (await projects.overview({ organizationId: "org", projectId: "throws" }))
        .ok,
    ).toBe(false);

    const noTags = client(transport, tasks, { tags: { forSubjects: failure } });
    expect(
      (await noTags.cards({ organizationId: "org", taskIds: ["t1"] })).ok,
    ).toBe(false);

    const quiet = client(
      transport,
      {
        ...tasks,
        facets: () => done([{ facet: "priority", values: [] }]),
        getProject: (id: string) =>
          id === "late" ? failure() : tasks.getProject(id),
      },
      { attachments: { counts: () => done({}) } },
    );

    const quietOverview = await quiet
      .overview({ organizationId: "org", projectId: "p" })
      .orThrow();

    expect(quietOverview.tasks).toEqual({});
    expect(quietOverview.files).toBe(0);
    expect((await quiet.dependencies({ projectId: "p" })).ok).toBe(false);

    for (const projectId of ["none", "empty", "bad-id"]) {
      const update = await projects
        .overview({ organizationId: "org", projectId })
        .orThrow();

      expect(update.update).toBeNull();
    }

    expect(
      (
        await projects
          .overview({ organizationId: "org", projectId: "bad-fields" })
          .orThrow()
      ).update,
    ).toEqual({ id: "u", health: "", body: "" });

    expect(
      await projects
        .saveInitiative({
          organizationId: "org",
          initiativeId: "bare",
          name: "Pay",
        })
        .orThrow(),
    ).toEqual({});
    expect(await projects.pageInitiatives("nope").orThrow()).toEqual([]);

    const unnamed = createProjects(
      asParts({
        transport,
        parts: {
          tasks,
          "saved-views": { page: () => done({ items: [] }) },
          "time-entries": { list: () => done([]), approve: () => done({}) },
          "billable-time": { invoice: () => done({}) },
        },
      }),
    );

    expect((await unnamed.views("p")).ok).toBe(false);
  });
});

describe("task row", () => {
  it("reads the milestone, the duplicate and the snooze", async () => {
    const row = {
      id: "w1",
      tenant_id: "o",
      number: 1,
      identifier: "TASK-1",
      title: "Pay",
      priority: 0,
      state: "triage",
      locked: false,
      rank: "a",
      milestone_id: "m1",
      duplicate_of: "w0",
      snoozed_until: "2026-12-01T00:00:00Z",
      created_at: "2026-11-01T00:00:00Z",
      updated_at: "2026-11-01T00:00:00Z",
      assignees: [],
    };

    const created = createTasks({
      transport: { call: () => Promise.resolve([row]) },
    });

    // oxlint-disable-next-line typescript/no-deprecated -- list still decodes the row until 0.70 (ADR 1077)
    const [item] = await created.list({ organizationId: "o" }).orThrow();

    expect(item?.milestoneId).toBe("m1");
    expect(item?.duplicateOfId).toBe("w0");
    expect(item?.snoozedUntil?.toString()).toBe("2026-12-01T00:00:00Z");
    expect(item?.fields).toEqual({});
  });
});
