import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { avatarPath, avatarRenderer, leftoverAvatarPaths } from "./storage.ts";
import {
  appRequestHeaders,
  supabaseClientEnv,
  supabaseServerEnv,
} from "./supabase.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

async function validate(
  schema: typeof supabaseServerEnv,
  value: Record<string, string>,
) {
  const result = await schema["~standard"].validate(value);
  return result.issues
    ? { issues: result.issues.map((issue) => issue.message) }
    : { value: result.value };
}

describe("env", () => {
  it("accepts sb_ keys and rejects legacy JWTs and swapped keys", async () => {
    expect(
      await validate(supabaseServerEnv, {
        SUPABASE_URL: PROJECT_URL,
        SUPABASE_PUBLISHABLE_KEY: "sb_publishable_x",
        SUPABASE_SECRET_KEY: "eyJhbGciOiJIUzI1NiJ9.e30.x",
      }),
    ).toEqual({
      issues: [
        expect.stringMatching(/^SUPABASE_SECRET_KEY is a legacy JWT key/),
      ],
    });
    expect(
      await validate(supabaseClientEnv, {
        SUPABASE_URL: PROJECT_URL,
        SUPABASE_PUBLISHABLE_KEY: "sb_secret_x",
      }),
    ).toEqual({
      issues: [
        expect.stringMatching(/^SUPABASE_PUBLISHABLE_KEY holds a secret key/),
      ],
    });
  });

  it("requires the secret key on the server only", async () => {
    const pub = {
      SUPABASE_URL: PROJECT_URL,
      SUPABASE_PUBLISHABLE_KEY: "sb_publishable_x",
    };
    expect((await validate(supabaseClientEnv, pub)).value).toMatchObject({
      url: PROJECT_URL,
    });
    expect((await validate(supabaseServerEnv, pub)).issues).toEqual([
      "SUPABASE_SECRET_KEY is not set",
    ]);
  });

  it("allows http on loopback only and strips trailing slashes", async () => {
    const key = { SUPABASE_PUBLISHABLE_KEY: "sb_publishable_x" };
    expect(
      (
        await validate(supabaseClientEnv, {
          ...key,
          SUPABASE_URL: "http://127.0.0.1:54321/",
        })
      ).value,
    ).toMatchObject({
      url: "http://127.0.0.1:54321",
    });
    expect(
      (
        await validate(supabaseClientEnv, {
          ...key,
          SUPABASE_URL: "http://db.example.com",
        })
      ).issues,
    ).toEqual([expect.stringMatching(/^SUPABASE_URL must use https/)]);
  });

  it("accepts the Vercel integration variable set with named key maps", async () => {
    const { value } = await validate(supabaseServerEnv, {
      NEXT_PUBLIC_SUPABASE_URL: PROJECT_URL,
      SUPABASE_PUBLISHABLE_KEYS: '{"default":"sb_publishable_x"}',
      SUPABASE_SECRET_KEYS: '{"default":"sb_secret_a","cron":"sb_secret_b"}',
      SUPABASE_ANON_KEY: "eyJ-legacy-and-ignored",
    });
    expect(value).toMatchObject({
      publishableKey: "sb_publishable_x",
      secretKeys: { default: "sb_secret_a", cron: "sb_secret_b" },
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      projectRef: "abcdefghijklmnopqrst",
    });
  });
});

describe("appRequestHeaders", () => {
  it("stamps channel, request id and the first forwarded client ip", () => {
    const request = new Request("https://app.test", {
      headers: {
        "x-request-id": "req-1",
        "x-forwarded-for": "203.0.113.7, 10.0.0.1",
      },
    });
    expect(appRequestHeaders(request, "web")).toEqual({
      "x-app-channel": "web",
      "x-request-id": "req-1",
      "x-client-ip": "203.0.113.7",
    });
  });

  it("falls back to a generated request id", () => {
    const headers = appRequestHeaders(
      new Request("https://app.test"),
      "mobile",
    );
    expect(headers["x-request-id"]).toMatch(/^[0-9a-f-]{36}$/);
    expect(headers).not.toHaveProperty("x-client-ip");
  });
});

describe("avatars", () => {
  const USER = "11111111-1111-4111-8111-111111111111";
  const storage = createClient(PROJECT_URL, "sb_publishable_x");
  const render = avatarRenderer(storage, PROJECT_URL);
  const object = `${PROJECT_URL}/storage/v1/object/public/avatars/${USER}/avatar.webp`;

  it("stores one file per user, named by type, and knows the leftovers", () => {
    expect(avatarPath(USER, "image/webp").data).toBe(`${USER}/avatar.webp`);
    expect(leftoverAvatarPaths(USER, `${USER}/avatar.webp`)).toEqual([
      `${USER}/avatar.jpg`,
      `${USER}/avatar.png`,
    ]);
  });

  it("rewrites a public object URL onto /render/image and keeps the version query", () => {
    const rendered = new URL(
      render(`${object}?v=3`, { width: 96, height: 96, resize: "cover" }),
    );
    expect(rendered.pathname).toBe(
      `/storage/v1/render/image/public/avatars/${USER}/avatar.webp`,
    );
    expect(Object.fromEntries(rendered.searchParams)).toEqual({
      width: "96",
      height: "96",
      resize: "cover",
      v: "3",
    });
  });

  it("leaves provider pictures, rendered URLs, other paths and junk alone", () => {
    for (const value of [
      "https://lh3.googleusercontent.com/a/photo.jpg",
      `${PROJECT_URL}/storage/v1/render/image/public/avatars/${USER}/avatar.webp?width=96`,
      `${PROJECT_URL}/storage/v1/object/public/avatars/${USER}/other.webp`,
      `${PROJECT_URL}/storage/v1/object/sign/avatars/${USER}/avatar.webp`,
      `https://elsewhere.supabase.co/storage/v1/object/public/avatars/${USER}/avatar.webp`,
      "not a url",
    ]) {
      expect(render(value, { width: 96 })).toBe(value);
    }
  });
});
