import { describe, expect, it, vi } from "vitest";

import type { Logger } from "../../src/core/logger.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

// client.observability.diagnostic_logging in supabase/sdk's capability matrix:
// https://github.com/supabase/sdk/blob/capability-matrix/v1.14.0/packages/capability-matrix/specs/client/observability/diagnostic_logging.md

const SECRET = "secret@example.com";

const recording = () => {
  const logger = {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  } satisfies Logger;
  return logger;
};

const conflict = () =>
  capturingClient((request) =>
    request.method === "GET"
      ? { body: [{ id: "c1" }, { id: "c2" }] }
      : {
          status: 409,
          body: {
            code: "23505",
            message: `duplicate key value violates unique constraint "contacts_email_key"`,
            details: `Key (email)=(${SECRET}) already exists.`,
            hint: null,
          },
        },
  );

describe("Supabase SDK diagnostic logging", () => {
  it("follows the pinned capability matrix", () => {
    expect(SPEC_PINS.supabaseSdkCapabilities).toBe("1.14.0");
  });

  it("emits nothing and registers no handler unless diagnostics is on", async () => {
    const logger = recording();
    const betterSupabase = defineSupabase(schema, { logger });
    expect(betterSupabase.events.has("query")).toBe(false);
    const db = betterSupabase.connect(conflict().client);
    await db.contacts.findMany({ select: ["id"], where: { email: SECRET } });
    expect(logger.debug).not.toHaveBeenCalled();
    expect(logger.info).not.toHaveBeenCalled();
  });

  it("logs request outcomes with timing at debug level", async () => {
    const logger = recording();
    const db = defineSupabase(schema, { logger, diagnostics: true }).connect(
      conflict().client,
    );
    const found = await db.contacts.findMany({
      select: ["id"],
      where: { email: SECRET },
    });
    expect(found.ok).toBe(true);
    expect(logger.debug).toHaveBeenCalledWith(
      expect.stringMatching(/^select contacts ok in \d+ms$/),
      expect.objectContaining({
        table: "contacts",
        operation: "select",
        ok: true,
        rows: 2,
        truncated: false,
        durationMs: expect.any(Number),
      }),
    );
    expect(logger.info).not.toHaveBeenCalled();
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it("never logs values, filters or database messages, and never changes the outcome", async () => {
    const logger = recording();
    const db = defineSupabase(schema, { logger, diagnostics: true }).connect(
      conflict().client,
    );
    const created = await db.contacts.create({
      organizationId: "o",
      email: SECRET,
    });
    expect(created.ok).toBe(false);
    expect(created.error?.kind).toBe("conflict");
    expect(logger.debug).toHaveBeenCalledWith("conflict error on contacts", {
      table: "contacts",
      kind: "conflict",
      status: 409,
      code: "23505",
    });
    const logged = JSON.stringify(logger.debug.mock.calls);
    expect(logged).not.toContain(SECRET);
    expect(logged).not.toContain("contacts_email_key");
    expect(logged).not.toContain("sb_publishable_test");
  });

  it("logs session refreshes and auth resolution without user ids", () => {
    const logger = recording();
    const betterSupabase = defineSupabase(schema, {
      logger,
      diagnostics: true,
    });
    betterSupabase.events.emit("refresh", {
      ok: true,
      shared: false,
      durationMs: 12.4,
    });
    betterSupabase.events.emit("auth", {
      source: "cookie",
      ok: true,
      userId: "8c5a3d3e-0000-4000-8000-000000000001",
    });
    expect(logger.debug.mock.calls).toEqual([
      [
        "session refresh ok in 12ms",
        { ok: true, shared: false, durationMs: 12.4 },
      ],
      ["auth from cookie: user", { source: "cookie", ok: true }],
    ]);
  });

  it("keeps results when the logger throws", async () => {
    const fail = () => {
      throw new Error("logger down");
    };
    const logger = { debug: fail, info: fail, warn: fail, error: fail };
    const db = defineSupabase(schema, { logger, diagnostics: true }).connect(
      conflict().client,
    );
    const found = await db.contacts.findMany({ select: ["id"] });
    expect(found.data).toEqual([{ id: "c1" }, { id: "c2" }]);
  });

  it("keeps one set of handlers on derived definitions", () => {
    const logger = recording();
    const derived = defineSupabase(schema, {
      logger,
      diagnostics: true,
    }).mapError((error) => new Error(error.message));
    derived.events.emit("refresh", { ok: false, shared: true, durationMs: 1 });
    expect(logger.debug).toHaveBeenCalledTimes(1);
  });
});
