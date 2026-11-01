import { describe, expect, it } from "vitest";

import { blockActions } from "../../../src/blocks/automations/index.ts";
import { quotesBlock } from "../../../src/blocks/quotes/manifest.ts";
import { tasksBlock } from "../../../src/blocks/tasks/manifest.ts";
import { createActionRegistry } from "../../../src/core/automation.ts";

describe("blockActions", () => {
  it("builds a registry from the manifests' handlers", () => {
    const actions = blockActions(
      { quotes: quotesBlock, tasks: tasksBlock, copy: tasksBlock },
      { clients: () => ({}) },
    );

    expect(
      createActionRegistry(actions)
        .kinds()
        .map((a) => a.kind)
        .toSorted(),
    ).toEqual(["quotes.from_deal", "tasks.from_conversation"]);
  });

  it("every shipped action kind has a handler or is listed as app-written", () => {
    const manifests = { quotes: quotesBlock, tasks: tasksBlock };

    for (const manifest of Object.values(manifests)) {
      for (const action of manifest.actions) {
        expect(Object.keys(manifest.handlers)).toContain(action.kind);
      }
    }
  });

  it("skips a lost deal and fails when the clients lack quotes", async () => {
    const [action] = blockActions(
      { quotes: quotesBlock },
      { clients: () => ({}) },
    );

    const result = await action!.run({
      action: { kind: "quotes.from_deal" },
      origin: { type: "automation", id: "a", name: "n" },
      context: {
        organizationId: "o",
        subjectType: "deal",
        subjectId: "d",
        payload: { outcome: "lost" },
      },
      key: "k",
    });

    expect(result).toMatchObject({ ok: true, data: { status: "skipped" } });
  });
});
