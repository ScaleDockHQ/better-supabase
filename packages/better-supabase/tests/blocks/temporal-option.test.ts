import { afterEach, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";

import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import { createAuditLog } from "../../src/blocks/audit/index.ts";
import { createJobs, createRateLimit } from "../../src/blocks/jobs/index.ts";
import { createOutbox } from "../../src/blocks/outbox/index.ts";
import { defineSettings } from "../../src/blocks/settings/index.ts";
import { applyTemporal } from "../../src/core/block-helpers.ts";
import { provideTemporal, providedTemporal } from "../../src/core/temporal.ts";

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
      () => createAuditLog({ transport, temporal: namespace }),
      () => createOutbox(sql, { source: "s", temporal: namespace }),
      () => createRateLimit(sql, { temporal: namespace }),
      () => createJobs(sql, {}, { temporal: namespace }),
      () => defineSettings({}).connect({ transport, temporal: namespace }),
    ];
    for (const create of creators) {
      provideTemporal(undefined);
      create();
      expect(providedTemporal()).toBe(namespace);
    }
    expect(globalThis.Temporal).toBe(before);
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
