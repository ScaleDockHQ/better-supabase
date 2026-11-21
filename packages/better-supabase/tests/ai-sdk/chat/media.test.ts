import { describe, expect, it } from "vitest";

import type {
  VideoJob,
  VideoJobStore,
  VideoStatus,
} from "../../../src/ai-sdk/chat/media.ts";
import type { AiFiles } from "../../../src/blocks/ai-files/ai-files.ts";

import {
  createMediaRoute,
  createVideoRoutes,
} from "../../../src/ai-sdk/chat/media.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const files = {
  files: {
    store: ({ file }: { file: { filename: string; mediaType: string } }) =>
      AsyncResult.ok({
        id: "00000000-0000-4000-8000-000000000001",
        bucket: "ai-files",
        path: `o1/${file.filename}`,
        filename: file.filename,
        mediaType: file.mediaType,
      }),
  },
} as unknown as AiFiles;

const ctx = { userId: "u1", organizationId: "o1" };

const post = (body: unknown) =>
  new Request("https://x.test/m", {
    method: "POST",
    body: JSON.stringify(body),
  });

const png = { uint8Array: new Uint8Array([1]), mediaType: "image/png" };

describe("createMediaRoute", () => {
  const base = {
    kind: "image" as const,
    model: "openai/gpt-image",
    files,
    authorize: () => undefined,
    run: async () => [png],
  };

  it("stores the output and answers file parts", async () => {
    const metered: unknown[] = [];

    const route = createMediaRoute({
      ...base,
      onFinish: (finish) => {
        metered.push(finish.files.length);
      },
    });

    const response = await route.respond(post({ prompt: "a cat" }), {
      ...ctx,
      waitUntil: (p) => void p,
    });

    const json = (await response.json()) as { files: { mediaType: string }[] };

    expect(json.files[0]?.mediaType).toBe("image/png");
    expect(metered).toEqual([1]);
  });

  it("stops at the access check before running the model", async () => {
    let ran = false;

    const route = createMediaRoute({
      ...base,
      authorize: () => ({ kind: "forbidden", message: "no", status: 403 }),
      run: async () => {
        ran = true;

        return [png];
      },
    });

    const response = await route.respond(post({ prompt: "x" }), ctx);

    expect(response.status).toBe(403);
    expect(ran).toBe(false);
  });

  it("keeps the response when the metering sink throws", async () => {
    const route = createMediaRoute({
      ...base,
      onFinish: () => {
        throw new Error("sink");
      },
    });

    const response = await route.respond(post({ prompt: "x" }), ctx);

    expect(response.status).toBe(200);
  });

  it("answers 429 over the quota and 400 without a prompt", async () => {
    const route = createMediaRoute({
      ...base,
      quota: async () => ({
        kind: "quota_exceeded",
        message: "used up",
        status: 429,
      }),
    });

    expect((await route.respond(post({ prompt: "x" }), ctx)).status).toBe(429);
    expect((await route.respond(post({}), ctx)).status).toBe(400);
  });
});

describe("createVideoRoutes", () => {
  function setup(next: VideoStatus) {
    const rows = new Map<string, VideoJob>();

    const jobs: VideoJobStore = {
      create: async (job) => void rows.set(job.id, job),
      get: async (id) => rows.get(id),
      update: async (id, patch) => {
        const row = rows.get(id);

        if (row) {
          rows.set(id, { ...row, ...patch });
        }
      },
    };

    let status = next;
    let polls = 0;

    const routes = createVideoRoutes({
      model: "google/veo",
      files,
      jobs,
      authorize: () => undefined,
      start: async () => ({ remote: "r1" }),
      status: async () => {
        polls += 1;

        return status;
      },
    });

    return {
      routes,
      rows,
      polls: () => polls,
      set: (s: VideoStatus) => (status = s),
    };
  }

  it("starts a job row and completes it on poll", async () => {
    const t = setup({ status: "pending" });
    const started = await t.routes.start(post({ prompt: "a wave" }), ctx);
    const { jobId } = (await started.json()) as { jobId: string };

    expect(started.status).toBe(202);
    expect(t.rows.get(jobId)?.status).toBe("pending");

    t.set({
      status: "succeeded",
      videos: [{ ...png, mediaType: "video/mp4" }],
    });

    const polled = await t.routes.poll(jobId, ctx);
    const view = (await polled.json()) as { status: string; files: unknown[] };

    expect(view.status).toBe("succeeded");
    expect(view.files).toHaveLength(1);
  });

  it("hides another user's job", async () => {
    const t = setup({ status: "pending" });
    const started = await t.routes.start(post({ prompt: "x" }), ctx);
    const { jobId } = (await started.json()) as { jobId: string };

    const other = await t.routes.poll(jobId, { ...ctx, userId: "u2" });

    expect(other.status).toBe(404);
  });

  it("treats the webhook as a wake-up and re-checks the status", async () => {
    const t = setup({ status: "failed", error: "blocked" });
    const started = await t.routes.start(post({ prompt: "x" }), ctx);
    const { jobId } = (await started.json()) as { jobId: string };

    // A forged body claiming success changes nothing: the provider is asked.
    const response = await t.routes.webhook(
      post({ jobId, status: "succeeded" }),
    );

    expect(response.status).toBe(200);
    expect(t.polls()).toBe(1);
    expect(t.rows.get(jobId)?.status).toBe("failed");

    const unknown = await t.routes.webhook(post({ jobId: "nope" }));

    expect(unknown.status).toBe(200);
  });
});
