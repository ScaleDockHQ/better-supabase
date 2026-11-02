import { afterEach, describe, expect, it, vi } from "vitest";

import type {
  WopiDrive,
  WopiTokenClaims,
} from "../../../src/blocks/drive/index.ts";

import { createWopiHost } from "../../../src/blocks/drive/index.ts";
import { toBase64Url } from "../../../src/core/base64.ts";
import { dbError } from "../../../src/core/errors.ts";
import { err, ok } from "../../../src/core/result.ts";

const NOW = Date.UTC(2026, 9, 31, 12);
const SECRET = "s3cret";

function node(over: Record<string, unknown> = {}) {
  return { id: "n1", name: "plan.docx", readOnly: false, ...over };
}

function hostOf(drive: Record<string, unknown>, extra = {}) {
  return createWopiHost({
    secret: SECRET,
    // SAFETY: tests implement only the drive methods a case calls.
    driveFor: () => drive as unknown as WopiDrive,
    now: () => NOW,
    ...extra,
  });
}

async function forge(payload: unknown): Promise<string> {
  const body = toBase64Url(JSON.stringify(payload));

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );

  return `${body}.${toBase64Url(new Uint8Array(mac))}`;
}

async function call(
  host: ReturnType<typeof hostOf>,
  path: string,
  init: RequestInit & { claims?: Partial<WopiTokenClaims> } = {},
) {
  const { accessToken } = await host.token({
    claims: { fileId: "n1", userId: "u1", canWrite: true, ...init.claims },
  });

  return host.handle(
    new Request(
      `https://x/wopi/files/${path}?access_token=${accessToken}`,
      init,
    ),
  );
}

const lockHeaders = (override: string, lock = "L", old?: string) => ({
  "x-wopi-override": override,
  "x-wopi-lock": lock,
  ...(old === undefined ? {} : { "x-wopi-oldlock": old }),
});

afterEach(() => vi.unstubAllGlobals());

describe("wopi host branches", () => {
  it("refuses signed tokens whose payload is malformed", async () => {
    const host = hostOf({ get: async () => ok(node()) });
    const exp = NOW + 60_000;

    const bad: unknown[] = [
      "text",
      null,
      { f: 1, u: "u1", w: true, e: exp },
      { f: "n1", u: 1, w: true, e: exp },
      { f: "n1", u: "u1", w: "yes", e: exp },
      { f: "n1", u: "u1", w: true, e: "soon" },
      { f: "n1", u: "u1", n: 5, w: true, e: exp },
      { f: "n1", u: "u1", w: true, e: NOW - 1 },
    ];

    for (const payload of bad) {
      const token = await forge(payload);

      const res = await host.handle(
        new Request(`https://x/wopi/files/n1?access_token=${token}`),
      );

      expect(res.status).toBe(401);
    }

    expect(
      (
        await host.handle(
          new Request("https://x/wopi/files/n1?access_token=a.b.c"),
        )
      ).status,
    ).toBe(401);
    expect(
      (await host.handle(new Request("https://x/wopi/files/n1"))).status,
    ).toBe(401);
  });

  it("accepts a forged token with a user name and shows it", async () => {
    const host = hostOf({ get: async () => ok(node()) });

    const token = await forge({
      f: "n1",
      u: "u1",
      n: "Ada",
      w: false,
      e: NOW + 60_000,
    });

    const res = await host.handle(
      new Request(`https://x/wopi/files/n1?access_token=${token}`),
    );

    expect(await res.json()).toMatchObject({
      UserFriendlyName: "Ada",
      UserCanWrite: false,
      ReadOnly: true,
    });
  });

  it("describes a bare node with defaults and flags a download-blocked file", async () => {
    const host = hostOf({
      get: async () => ok(node({ downloadable: false, readOnly: true })),
    });

    const res = await call(host, "n1", { claims: { userName: "Ada" } });

    expect(await res.json()).toMatchObject({
      OwnerId: "",
      Size: 0,
      Version: "",
      UserFriendlyName: "Ada",
      UserCanWrite: false,
      ReadOnly: true,
      DisablePrint: true,
    });
  });

  it("falls back to the user id as the friendly name", async () => {
    const host = hostOf({ get: async () => ok(node()) });

    expect(await (await call(host, "n1")).json()).toMatchObject({
      UserFriendlyName: "u1",
      DisablePrint: false,
    });
  });

  it("maps errors to statuses, including out of range and 4xx pass-through", async () => {
    const statusFor = async (error: ReturnType<typeof dbError>) =>
      (await call(hostOf({ get: async () => err(error) }), "n1")).status;

    expect(await statusFor(dbError("unauthorized", "no"))).toBe(401);
    expect(await statusFor(dbError("forbidden", "no"))).toBe(401);
    expect(await statusFor(dbError("rate_limited", "slow"))).toBe(429);
    expect(await statusFor(dbError("unexpected", "x", { status: 200 }))).toBe(
      500,
    );
    expect(await statusFor(dbError("unexpected", "x", { status: 600 }))).toBe(
      500,
    );
  });

  it("serves GetFile without a version header when the node lookup fails", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("bytes")),
    );

    const host = hostOf({
      download: async () =>
        ok({
          attachment: { mimeType: "text/plain" },
          signedUrl: "https://s/get",
        }),
      get: async () => err(dbError("not_found", "gone")),
    });

    const res = await call(host, "n1/contents");

    expect(res.status).toBe(200);
    expect(res.headers.get("x-wopi-itemversion")).toBeNull();
    expect(res.headers.get("content-type")).toBe("text/plain");
  });

  it("reports GetFile errors from the drive", async () => {
    const host = hostOf({
      download: async () => err(dbError("not_found", "gone")),
    });

    expect((await call(host, "n1/contents")).status).toBe(404);
  });

  it("serves GetFile with an empty version for a node without an attachment", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("bytes")),
    );

    const host = hostOf({
      download: async () =>
        ok({ attachment: { mimeType: "x/y" }, signedUrl: "https://s/get" }),
      get: async () => ok(node()),
    });

    expect(
      (await call(host, "n1/contents")).headers.get("x-wopi-itemversion"),
    ).toBe("");
  });

  it("answers PutFile errors from get, upload and commit", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("")),
    );

    const lockedNode = node({
      lockedBy: "u1",
      lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
      lockNote: "wopi:L",
      file: { size: 3 },
    });

    const post = (host: ReturnType<typeof hostOf>) =>
      call(host, "n1/contents", {
        method: "POST",
        headers: { "x-wopi-lock": "L" },
        body: "abc",
      });

    expect(
      (await post(hostOf({ get: async () => err(dbError("not_found", "x")) })))
        .status,
    ).toBe(404);

    const upload = hostOf({
      get: async () => ok(lockedNode),
      uploadRevision: async () => err(dbError("forbidden", "no")),
    });

    expect((await post(upload)).status).toBe(401);

    const commit = hostOf({
      get: async () => ok(lockedNode),
      uploadRevision: async () =>
        ok({ signedUrl: "https://s/put", attachment: { id: "a2" } }),
      commit: async () => err(dbError("conflict", "stale")),
    });

    expect((await post(commit)).status).toBe(409);
  });

  it("uploads with a default mime type and an empty unlocked file", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("")),
    );

    const sizes: unknown[] = [];

    const host = hostOf({
      get: async () => ok(node()),
      uploadRevision: async (input: unknown) => {
        sizes.push(input);

        return ok({ signedUrl: "https://s/put", attachment: { id: "a2" } });
      },
      commit: async () => ok(node()),
    });

    const res = await call(host, "n1/contents", {
      method: "POST",
      body: "abc",
    });

    expect(res.status).toBe(200);
    expect(res.headers.get("x-wopi-itemversion")).toBe("");
    expect(sizes).toEqual([
      { id: "n1", file: { mimeType: "application/octet-stream", size: 3 } },
    ]);
  });

  it("returns an empty lock id for GetLock on an unlocked file and the live id on a locked one", async () => {
    const unlocked = hostOf({ get: async () => ok(node()) });

    const res = await call(unlocked, "n1", {
      method: "POST",
      headers: { "x-wopi-override": "GET_LOCK" },
    });

    expect(res.headers.get("x-wopi-lock")).toBe("");

    const taken = hostOf({
      get: async () =>
        ok(
          node({
            lockedBy: "u1",
            lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 1000),
            lockNote: "person check-out",
          }),
        ),
    });

    const other = await call(taken, "n1", {
      method: "POST",
      headers: lockHeaders("LOCK"),
    });

    expect(other.status).toBe(409);
    expect(other.headers.get("x-wopi-lock")).toBe("");
  });

  it("reports a lock error from get and refuses lock calls for read-only tokens", async () => {
    const missing = hostOf({ get: async () => err(dbError("not_found", "x")) });

    expect(
      (
        await call(missing, "n1", {
          method: "POST",
          headers: lockHeaders("LOCK"),
        })
      ).status,
    ).toBe(404);

    const readOnly = hostOf({ get: async () => ok(node()) });

    expect(
      (
        await call(readOnly, "n1", {
          method: "POST",
          headers: lockHeaders("LOCK"),
          claims: { canWrite: false },
        })
      ).status,
    ).toBe(401);
  });

  it("walks the refresh, unlock and relock mismatches and errors", async () => {
    const live = (id: string) =>
      node({
        lockedBy: "u1",
        lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
        lockNote: `wopi:${id}`,
      });

    const host = hostOf({
      get: async () => ok(live("L")),
      lock: async () => ok(live("M")),
      unlock: async () => err(dbError("forbidden", "no")),
    });

    const op = (override: string, lock = "L", old?: string) =>
      call(host, "n1", {
        method: "POST",
        headers: lockHeaders(override, lock, old),
      });

    expect((await op("REFRESH_LOCK", "L")).status).toBe(200);
    expect((await op("REFRESH_LOCK", "X")).status).toBe(409);
    expect((await op("UNLOCK", "X")).status).toBe(409);
    expect((await op("UNLOCK", "L")).status).toBe(401);
    expect((await op("UNLOCK_AND_RELOCK", "M", "L")).status).toBe(200);
    expect((await op("UNLOCK_AND_RELOCK", "M", "Z")).status).toBe(409);
    expect((await op("LOCK", "L")).status).toBe(200);
  });

  it("refuses unlock on an unlocked file and relock without an old lock", async () => {
    const host = hostOf({
      get: async () => ok(node()),
      lock: async () => ok(node()),
    });

    const op = (override: string, lock: string, old?: string) =>
      call(host, "n1", {
        method: "POST",
        headers: lockHeaders(override, lock, old),
      });

    expect((await op("UNLOCK", "L")).status).toBe(409);
    expect((await op("UNLOCK_AND_RELOCK", "L", "")).status).toBe(409);
    expect((await op("REFRESH_LOCK", "L")).status).toBe(409);
  });

  it("surfaces lock failures from the drive", async () => {
    const host = hostOf({
      get: async () => ok(node()),
      lock: async () => err(dbError("forbidden", "no")),
    });

    expect(
      (await call(host, "n1", { method: "POST", headers: lockHeaders("LOCK") }))
        .status,
    ).toBe(401);
  });

  it("answers a successful unlock with the node version", async () => {
    const host = hostOf({
      get: async () =>
        ok(
          node({
            lockedBy: "u1",
            lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
            lockNote: "wopi:L",
          }),
        ),
      unlock: async () => ok(node({ attachmentId: "a9" })),
    });

    const res = await call(host, "n1", {
      method: "POST",
      headers: lockHeaders("UNLOCK"),
    });

    expect(res.status).toBe(200);
    expect(res.headers.get("x-wopi-itemversion")).toBe("a9");
  });

  it("honours a custom prefix, lock duration and the real clock by default", async () => {
    const locks: Temporal.Instant[] = [];

    const host = createWopiHost({
      secret: SECRET,
      prefix: "/office/",
      lockMinutes: 5,
      // SAFETY: tests implement only the drive methods a case calls.
      driveFor: () =>
        ({
          get: async () => ok(node()),
          lock: async (o: { until: Temporal.Instant }) => {
            locks.push(o.until);

            return ok(node());
          },
        }) as unknown as WopiDrive,
    });

    const { accessToken, accessTokenTtl } = await host.token({
      claims: { fileId: "n1", userId: "u1", canWrite: true },
      ttlSeconds: 60,
    });

    expect(accessTokenTtl).toBeGreaterThan(Date.now());

    const res = await host.handle(
      new Request(`https://x/office/files/n1?access_token=${accessToken}`, {
        method: "POST",
        headers: lockHeaders("LOCK"),
      }),
    );

    expect(res.status).toBe(200);
    expect((locks[0]?.epochMilliseconds ?? 0) - Date.now()).toBeLessThanOrEqual(
      300_000,
    );
  });

  it("reports an empty lock for a person's check-out on GetLock and PutFile", async () => {
    const checkedOut = node({
      lockedBy: "u2",
      lockedUntil: Temporal.Instant.fromEpochMilliseconds(NOW + 60_000),
      lockNote: "person check-out",
    });

    const host = hostOf({ get: async () => ok(checkedOut) });

    const getLock = await call(host, "n1", {
      method: "POST",
      headers: { "x-wopi-override": "GET_LOCK" },
    });

    expect(getLock.status).toBe(200);
    expect(getLock.headers.get("x-wopi-lock")).toBe("");

    const put = await call(host, "n1/contents", {
      method: "POST",
      body: "abc",
    });

    expect(put.status).toBe(409);
    expect(put.headers.get("x-wopi-lock")).toBe("");
  });

  it("refuses a token whose payload is not JSON", async () => {
    const host = hostOf({ get: async () => ok(node()) });
    const body = toBase64Url("not json");

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const mac = await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(body),
    );

    const token = `${body}.${toBase64Url(new Uint8Array(mac))}`;

    expect(
      (
        await host.handle(
          new Request(`https://x/wopi/files/n1?access_token=${token}`),
        )
      ).status,
    ).toBe(401);
  });
});
