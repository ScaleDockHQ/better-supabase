import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { err, ok } from "../../src/core/result.ts";
import { createImageLoader } from "../../src/next/image/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";
const CUSTOMER = `c${String(Date.now())}`;

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/storage/v1/status`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();

// Own bucket ids: `customer-logos` belongs to the example app's migration.
const logos = defineBucket({
  id: "bs-it-logos",
  path: "{orgId}/{customerId}/logo/{version}.webp",
  policy: "tenant",
  fileSizeLimit: "5MiB",
  allowedMimeTypes: ["image/png", "image/jpeg", "image/webp"],
});

const avatars = defineBucket({
  id: "bs-it-avatars",
  path: "{orgId}/{file}",
  public: true,
  policy: "public",
});

const image = (text: string) => new Blob([text], { type: "image/webp" });

describe.skipIf(!live)("Storage kit", async () => {
  const user = logos.connect(
    createClient(url, publishableKey, {
      accessToken: () =>
        signLocalJwt({ sub: USER, role: "authenticated", tenant_id: ACME }),
    }),
  );
  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const admin = logos.connect(service);
  const publicAdmin = avatars.connect(service);
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  beforeAll(async () => {
    await pool.query(logos.sql());
    await pool.query(avatars.sql());
  });
  afterAll(async () => {
    const all = await admin.list({ orgId: ACME, customerId: CUSTOMER });
    if (all.ok) await admin.remove(all.data.map((object) => object.path));
    await publicAdmin.remove([{ orgId: ACME, file: `${CUSTOMER}.webp` }]);
    await pool.end();
  });

  it("has no drift after applying its SQL", async () => {
    const { rows } = await pool.query<{
      public: boolean;
      file_size_limit: string | null;
      allowed_mime_types: string[] | null;
    }>(
      "select public, file_size_limit, allowed_mime_types from storage.buckets where id = $1",
      [logos.id],
    );
    const row = rows[0]!;
    expect(
      logos.drift({
        public: row.public,
        fileSizeLimit: Number(row.file_size_limit),
        allowedMimeTypes: row.allowed_mime_types,
      }),
    ).toEqual([]);
  });

  it("uploads inside the tenant and is denied outside it", async () => {
    const own = await user.upload(
      { orgId: ACME, customerId: CUSTOMER, version: "v1" },
      image("one"),
    );
    expect(own).toEqual(ok({ path: `${ACME}/${CUSTOMER}/logo/v1.webp` }));

    const other = await user.upload(
      { orgId: OTHER, customerId: CUSTOMER, version: "v1" },
      image("x"),
    );
    expect(other.error?.kind).toBe("forbidden");

    const outside = await user.upload(
      `${ACME}/${CUSTOMER}/elsewhere.webp`,
      image("x"),
    );
    expect(outside.error).toMatchObject({ kind: "invalid_input" });

    const conflict = await user.upload(
      { orgId: ACME, customerId: CUSTOMER, version: "v1" },
      image("again"),
    );
    expect(conflict.error?.kind).toBe("conflict");

    const wrongType = await user.upload(
      { orgId: ACME, customerId: CUSTOMER, version: "v9" },
      new Blob(["x"], { type: "text/plain" }),
    );
    expect(wrongType.error).toMatchObject({
      kind: "invalid_input",
      status: 415,
    });
  });

  it("serves signed URLs and checks existence", async () => {
    const target = { orgId: ACME, customerId: CUSTOMER, version: "v1" };
    const signed = await user.signedUrl(target, { ttl: "minute" }).orThrow();
    expect(await (await fetch(signed)).text()).toBe("one");
    expect(await user.exists(target).orThrow()).toBe(true);
    expect(await user.exists({ ...target, version: "nope" }).orThrow()).toBe(
      false,
    );
    expect(await (await user.download(target).orThrow()).text()).toBe("one");
    const rendered = new URL(
      await user.renderUrl(target, { width: 64, height: 64 }).orThrow(),
    );
    // `/object/sign/` when the stack has image transformations disabled
    // (no imgproxy), `/render/image/sign/` when they're on.
    expect(rendered.pathname).toMatch(
      new RegExp(
        `^/storage/v1/(render/image|object)/sign/bs-it-logos/${ACME}/${CUSTOMER}/logo/v1\\.webp$`,
      ),
    );
    expect(rendered.searchParams.get("token")).toBeTruthy();
  });

  it("copies and moves objects as the tenant user", async () => {
    const target = { orgId: ACME, customerId: CUSTOMER, version: "v1" };
    const copy = { ...target, version: "copy" };
    const moved = { ...target, version: "moved" };
    expect(await user.copy(target, copy).orThrow()).toEqual({
      path: `${ACME}/${CUSTOMER}/logo/copy.webp`,
    });
    await user.move(copy, moved).orThrow();
    expect(await user.exists(copy).orThrow()).toBe(false);
    expect(await (await user.download(moved).orThrow()).text()).toBe("one");
    await user.remove([moved]).orThrow();
  });

  it("builds public render URLs the next/image loader keeps in sync", async () => {
    const target = { orgId: ACME, file: `${CUSTOMER}.webp` };
    await publicAdmin.upload(target, image("face"), { upsert: true }).orThrow();
    const object = publicAdmin.publicUrl(target).data!;
    expect(await (await fetch(object)).text()).toBe("face");
    const rendered = await publicAdmin
      .renderUrl(target, { width: 128, quality: 60 })
      .orThrow();
    expect(rendered).toBe(
      `${url}/storage/v1/render/image/public/bs-it-avatars/${ACME}/${CUSTOMER}.webp?width=128&quality=60`,
    );
    expect(
      createImageLoader({ url })({ src: object, width: 128, quality: 60 }),
    ).toBe(rendered);
  });

  it("replaces objects and rolls back when the commit fails", async () => {
    const v1 = logos.path({
      orgId: ACME,
      customerId: CUSTOMER,
      version: "v1",
    }).data!;
    let stored = v1;
    const replaced = await user
      .replace(
        { orgId: ACME, customerId: CUSTOMER, version: "v2" },
        image("two"),
        {
          previous: stored,
          commit: (path) => {
            stored = path;
          },
        },
      )
      .orThrow();
    expect(replaced).toEqual({
      path: `${ACME}/${CUSTOMER}/logo/v2.webp`,
      removed: v1,
    });
    expect(await user.exists(v1).orThrow()).toBe(false);

    const failed = await user.replace(
      { orgId: ACME, customerId: CUSTOMER, version: "v3" },
      image("three"),
      {
        previous: stored,
        commit: () =>
          err({ kind: "conflict", message: "row changed", status: 409 }),
      },
    );
    expect(failed.error?.message).toBe("row changed");
    expect(
      await user
        .exists({ orgId: ACME, customerId: CUSTOMER, version: "v3" })
        .orThrow(),
    ).toBe(false);
    expect(await user.exists(stored).orThrow()).toBe(true);
  });

  it("reserves signed uploads", async () => {
    const reservation = await user
      .reserve({ orgId: ACME, customerId: CUSTOMER, version: "r1" })
      .orThrow();
    expect(reservation.path).toBe(`${ACME}/${CUSTOMER}/logo/r1.webp`);
    await user.uploadReserved(reservation, image("reserved")).orThrow();
    expect(await user.exists(reservation.path).orThrow()).toBe(true);
  });

  it("lists and sweeps orphans", async () => {
    const within = { orgId: ACME, customerId: CUSTOMER };
    const listed = await user.list(within).orThrow();
    expect(listed.map((object) => object.path).sort()).toEqual([
      `${ACME}/${CUSTOMER}/logo/r1.webp`,
      `${ACME}/${CUSTOMER}/logo/v2.webp`,
    ]);
    expect(listed[0]).toMatchObject({ contentType: "image/webp" });

    const keep = `${ACME}/${CUSTOMER}/logo/v2.webp`;
    const dry = await user
      .sweep({
        within,
        olderThan: Temporal.Duration.from({ minutes: -1 }),
        referenced: () => [keep],
        dryRun: true,
      })
      .orThrow();
    expect(dry).toEqual({
      scanned: 2,
      orphans: [`${ACME}/${CUSTOMER}/logo/r1.webp`],
      removed: [],
    });
    const young = await user
      .sweep({
        within,
        olderThan: Temporal.Duration.from({ hours: 1 }),
        referenced: () => [],
      })
      .orThrow();
    expect(young.orphans).toEqual([]);
    const swept = await user
      .sweep({
        within,
        olderThan: Temporal.Duration.from({ minutes: -1 }),
        referenced: (paths) => paths.filter((path) => path === keep),
      })
      .orThrow();
    expect(swept.removed).toEqual([`${ACME}/${CUSTOMER}/logo/r1.webp`]);
    expect(
      (await user.list(within).orThrow()).map((object) => object.path),
    ).toEqual([keep]);
  });
});
