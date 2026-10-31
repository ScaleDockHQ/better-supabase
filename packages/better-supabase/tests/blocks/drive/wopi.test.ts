import { afterEach, describe, expect, it, vi } from "vitest";

import type { WopiDrive } from "../../../src/blocks/drive/index.ts";

import { createWopiHost } from "../../../src/blocks/drive/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { ok, err } from "../../../src/core/result.ts";

const NOW = Date.UTC(2026, 9, 31, 12);

function node(over: Record<string, unknown> = {}) {
  return {
    id: "n1",
    name: "plan.docx",
    createdBy: "u1",
    attachmentId: "a1",
    readOnly: false,
    file: { mimeType: "application/msword", size: 5 },
    lockedBy: undefined,
    lockedUntil: undefined,
    lockNote: undefined,
    ...over,
  };
}

function setup(initial: Record<string, unknown> = {}) {
  const state = { node: node(initial) };
  const calls: string[] = [];

  const drive = {
    get: async () => ok(state.node),
    lock: async (_id: string, o: { until: Temporal.Instant; note: string }) => {
      calls.push(`lock ${o.note}`);
      state.node = node({
        lockedBy: "u1",
        lockedUntil: o.until,
        lockNote: o.note,
      });

      return ok(state.node);
    },
    unlock: async () => {
      calls.push("unlock");
      state.node = node();

      return ok(state.node);
    },
    download: async () =>
      ok({
        attachment: { mimeType: "application/msword" },
        signedUrl: "https://s/get",
      }),
    uploadRevision: async (_id: string, f: { size: number }) => {
      calls.push(`revision ${f.size}`);

      return ok({ signedUrl: "https://s/put", attachment: { id: "a2" } });
    },
    commit: async () => {
      calls.push("commit");
      state.node = node({ ...state.node, attachmentId: "a2" });

      return ok(state.node);
    },
  } as unknown as WopiDrive;

  const host = createWopiHost({
    secret: "s3cret",
    driveFor: () => drive,
    now: () => NOW,
  });

  return { host, calls, state };
}

async function request(
  host: ReturnType<typeof setup>["host"],
  path: string,
  init: RequestInit & {
    claims?: Partial<Parameters<typeof host.token>[0]>;
  } = {},
) {
  const { accessToken } = await host.token({
    fileId: "n1",
    userId: "u1",
    canWrite: true,
    ...init.claims,
  });

  return host.handle(
    new Request(
      `https://x/wopi/files/${path}?access_token=${accessToken}`,
      init,
    ),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("createWopiHost", () => {
  it("answers CheckFileInfo", async () => {
    const { host } = setup();
    const res = await request(host, "n1");

    expect(await res.json()).toMatchObject({
      BaseFileName: "plan.docx",
      Size: 5,
      UserCanWrite: true,
      SupportsLocks: true,
      Version: "a1",
    });
  });

  it("refuses a missing, forged, expired or mismatched token", async () => {
    const { host } = setup();

    const { accessToken } = await host.token({
      fileId: "n1",
      userId: "u1",
      canWrite: true,
    });

    const [payload] = accessToken.split(".");

    const old = createWopiHost({
      secret: "s3cret",
      driveFor: () => ({}) as WopiDrive,
      now: () => NOW + 3_600_000,
    });

    const status = async (h: typeof host, p: string, t: string) =>
      (
        await h.handle(
          new Request(`https://x/wopi/files/${p}?access_token=${t}`),
        )
      ).status;

    expect(await status(host, "n1", "")).toBe(401);
    expect(await status(host, "n1", `${payload}.AAAA`)).toBe(401);
    expect(await status(host, "n2", accessToken)).toBe(401);
    expect(await status(old, "n1", accessToken)).toBe(401);
  });

  it("locks, refreshes, rejects another id and unlocks", async () => {
    const { host, calls } = setup();

    const op = (
      override: string,
      lock: string,
      extra: Record<string, string> = {},
    ) =>
      request(host, "n1", {
        method: "POST",
        headers: { "x-wopi-override": override, "x-wopi-lock": lock, ...extra },
      });

    expect((await op("LOCK", "L1")).status).toBe(200);
    expect((await op("LOCK", "L2")).status).toBe(409);
    expect((await op("LOCK", "L2")).headers.get("x-wopi-lock")).toBe("L1");
    expect((await op("REFRESH_LOCK", "L1")).status).toBe(200);
    expect((await op("UNLOCK", "L2")).status).toBe(409);
    expect(
      (await op("UNLOCK_AND_RELOCK", "L3", { "x-wopi-oldlock": "L1" })).status,
    ).toBe(200);
    expect((await op("GET_LOCK", "")).headers.get("x-wopi-lock")).toBe("L3");
    expect((await op("UNLOCK", "L3")).status).toBe(200);
    expect(calls).toContain("lock wopi:L1");
    expect(calls).toContain("unlock");
  });

  it("answers 409 with an empty lock for a person's check-out", async () => {
    const { host } = setup({
      lockedBy: "u2",
      lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
      lockNote: "editing",
    });

    const res = await request(host, "n1", {
      method: "POST",
      headers: { "x-wopi-override": "LOCK", "x-wopi-lock": "L1" },
    });

    expect(res.status).toBe(409);
    expect(res.headers.get("x-wopi-lock")).toBe("");
  });

  it("takes PutFile only under the matching lock", async () => {
    const fetchMock = vi.fn(async () => new Response("ok"));

    vi.stubGlobal("fetch", fetchMock);

    const { host, calls } = setup({
      lockedBy: "u1",
      lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
      lockNote: "wopi:L1",
    });

    const put = (lock: string) =>
      request(host, "n1/contents", {
        method: "POST",
        headers: { "x-wopi-lock": lock },
        body: "hello!",
      });

    expect((await put("other")).status).toBe(409);

    const res = await put("L1");

    expect(res.status).toBe(200);
    expect(res.headers.get("x-wopi-itemversion")).toBe("a2");
    expect(calls).toEqual(["revision 6", "commit"]);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://s/put",
      expect.objectContaining({ method: "PUT" }),
    );
  });

  it("refuses PutFile on an unlocked file with content and for a read-only token", async () => {
    const { host } = setup();

    expect(
      (await request(host, "n1/contents", { method: "POST", body: "x" }))
        .status,
    ).toBe(409);
    expect(
      (
        await request(host, "n1/contents", {
          method: "POST",
          body: "x",
          claims: { canWrite: false },
        })
      ).status,
    ).toBe(401);
  });

  it("streams GetFile and maps errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("bytes")),
    );

    const { host } = setup();
    const res = await request(host, "n1/contents");

    expect(await res.text()).toBe("bytes");
    expect(res.headers.get("x-wopi-itemversion")).toBe("a1");

    const missing = createWopiHost({
      secret: "s3cret",
      now: () => NOW,
      driveFor: () =>
        ({
          get: async () => err(dbError("not_found", "gone")),
        }) as unknown as WopiDrive,
    });

    expect((await request(missing, "n1")).status).toBe(404);
  });
});
