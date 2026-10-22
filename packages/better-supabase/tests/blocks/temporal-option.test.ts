import { Temporal as Polyfill } from "temporal-polyfill";
import { afterEach, describe, expect, it, onTestFinished, vi } from "vitest";

import type { BlockEvent } from "../../src/core/block-events.ts";
import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";

import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import { createAudit } from "../../src/blocks/audit/index.ts";
import { createOutbox } from "../../src/blocks/outbox/index.ts";
import { createQueue, createRateLimit } from "../../src/blocks/queue/index.ts";
import {
  createSettings,
  defineSettings,
} from "../../src/blocks/settings/index.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { applyTemporal } from "../../src/core/block-helpers.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { provideTemporal, providedTemporal } from "../../src/core/temporal.ts";
import { schema } from "../fixtures/generated-camel.ts";

const transport: BlockTransport = { call: async () => null };
const sql: SqlClient = { queryRaw: async () => [] };

describe("the temporal option of block creators", () => {
  afterEach(() => {
    provideTemporal(undefined);
  });

  it("provides the namespace without touching globalThis", () => {
    const namespace = { ...Temporal };
    const before: unknown = globalThis.Temporal;

    const creators = [
      () => createAnnouncements({ transport, temporal: namespace }),
      () => createAudit({ transport, temporal: namespace }),
      () => createOutbox({ transport, source: "s", temporal: namespace }),
      () => createRateLimit({ sql, temporal: namespace }),
      () => createQueue({ sql, queues: {}, temporal: namespace }),
      () =>
        createSettings({
          settings: defineSettings({}),
          transport,
          temporal: namespace,
        }),
    ];

    for (const create of creators) {
      provideTemporal(undefined);
      create();
      expect(providedTemporal()).toBe(namespace);
    }

    expect(globalThis.Temporal).toBe(before);
  });

  it("parses block rows with the injected namespace and no global", async () => {
    vi.stubGlobal("Temporal", undefined);
    onTestFinished(() => {
      vi.unstubAllGlobals();
    });

    const row = {
      id: "a1",
      title: "Maintenance",
      body: "Tonight",
      severity: "info",
      href: null,
      audience: "all",
      targets: [],
      starts_at: "2026-01-01T00:00:00Z",
      ends_at: null,
      dismissible: true,
      created_by: "staff",
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z",
    };

    const announcements = createAnnouncements({
      transport: { call: async () => [row] },
      temporal: Polyfill,
    });

    const [first] = await announcements.listActive().orThrow();
    expect(first?.startsAt).toBeInstanceOf(Polyfill.Instant);
    expect(first?.startsAt.toString()).toBe("2026-01-01T00:00:00Z");
  });

  it("stamps block events with the definition's now option", () => {
    const time = Temporal.Instant.from("2026-10-01T12:00:00Z");
    const betterSupabase = defineSupabase(schema, { now: () => time });
    const seen: BlockEvent[] = [];
    betterSupabase.on("block", (event) => {
      seen.push(event);
    });
    emitBlockEvent(betterSupabase.events, "support.started", {
      sessionId: "s1",
      adminId: "u1",
      targetUserId: "u2",
      reason: "ticket",
    });
    expect(seen.map((event) => event.time)).toEqual([time]);
  });

  it("leaves the provided namespace alone without the option", () => {
    const namespace = { ...Temporal };
    provideTemporal(namespace);
    applyTemporal({});
    applyTemporal(undefined);
    createAnnouncements({ transport });
    expect(providedTemporal()).toBe(namespace);
  });
});
