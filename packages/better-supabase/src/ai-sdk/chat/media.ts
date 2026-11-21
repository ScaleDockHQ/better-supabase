import type { AiFilePart } from "../../blocks/ai-chat/message.ts";
import type { AiFiles } from "../../blocks/ai-files/ai-files.ts";
import type { DbError } from "../../core/errors.ts";
import type { GeneratedFileLike } from "../files/files.ts";
import type { GatewayOptions } from "../gateway-options.ts";

import { isRecord } from "../../core/guards.ts";
import { problemResponse } from "../../core/problem.ts";
import { aiErrorToDbError } from "../errors.ts";
import { saveGeneratedFiles } from "../files/files.ts";
import { gatewayOptions, problem429 } from "../gateway.ts";
import { badRequest, readJson } from "../http.ts";

/** Who asks for one media generation. */
export interface MediaContext {
  readonly userId: string;
  readonly organizationId: string;
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** The access check that runs first; an error answers with its status. */
export type MediaAuthorize = (
  context: MediaContext,
  body: Readonly<Record<string, unknown>>,
) => Promise<DbError | undefined> | DbError | undefined;

export interface MediaRouteOptions {
  /** What the route generates; also the gateway `feature` tag. */
  readonly kind: "image" | "speech";
  readonly model: string;
  readonly files: AiFiles;
  readonly authorize: MediaAuthorize;
  /** Calls `generateImage` or `generateSpeech` and returns the files. */
  readonly run: (args: {
    readonly prompt: string;
    readonly body: Readonly<Record<string, unknown>>;
    readonly model: string;
    readonly abortSignal: AbortSignal;
    readonly providerOptions: { readonly gateway: GatewayOptions };
    readonly context: MediaContext;
  }) => PromiseLike<readonly GeneratedFileLike[]>;
  readonly quota?: (organizationId: string) => Promise<DbError | undefined>;
  /** Runs after the files are stored, such as to meter one generation. */
  readonly onFinish?: (finish: {
    readonly prompt: string;
    readonly files: readonly AiFilePart[];
    readonly context: MediaContext;
  }) => void | Promise<void>;
}

export interface MediaRoute {
  respond(request: Request, context: MediaContext): Promise<Response>;
}

async function readPrompt(
  request: Request,
): Promise<
  | {
      readonly body: Readonly<Record<string, unknown>>;
      readonly prompt: string;
    }
  | Response
> {
  const body = await readJson(request);

  if (!isRecord(body)) {
    return badRequest("Expected a JSON object.");
  }

  const prompt = body["prompt"];

  return typeof prompt === "string" && prompt.trim() !== ""
    ? { body, prompt }
    : badRequest("Expected a prompt.");
}

/**
 * A route for one image or speech generation. It checks access, then the quota,
 * calls `run` with the gateway tags, stores the output in Storage as
 * `generated` files and answers `{ files }` with file parts. `onFinish` meters
 * the call and can't change the response.
 */
export function createMediaRoute(options: MediaRouteOptions): MediaRoute {
  return {
    async respond(request, context) {
      const read = await readPrompt(request);

      if (read instanceof Response) {
        return read;
      }

      const denied = await options.authorize(context, read.body);

      if (denied) {
        return problemResponse(denied);
      }

      const exceeded = await options.quota?.(context.organizationId);

      if (exceeded) {
        return problem429(exceeded);
      }

      let generated: readonly GeneratedFileLike[];

      try {
        generated = await options.run({
          prompt: read.prompt,
          body: read.body,
          model: options.model,
          abortSignal: request.signal,
          providerOptions: gatewayOptions({
            userId: context.userId,
            organizationId: context.organizationId,
            feature: options.kind,
          }),
          context,
        });
      } catch (cause) {
        return problemResponse(aiErrorToDbError(cause));
      }

      const saved = await saveGeneratedFiles(options.files, generated, {
        organizationId: context.organizationId,
        ownerId: context.userId,
      });

      if (!saved.ok) {
        return problemResponse(saved.error);
      }

      const { onFinish } = options;

      if (onFinish !== undefined) {
        const settled = (async () => {
          try {
            await onFinish({ prompt: read.prompt, files: saved.data, context });
          } catch {
            // A sink never changes the result.
          }
        })();

        context.waitUntil?.(settled);
      }

      return Response.json({ files: saved.data });
    },
  };
}

/** One video generation the provider runs after the request returned. */
export interface VideoJob {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly prompt: string;
  /** What the provider needs to ask for the status (its job reference). */
  readonly providerJob: unknown;
  readonly status: "pending" | "succeeded" | "failed";
  readonly files?: readonly AiFilePart[];
  readonly error?: string;
}

/** The job rows: a table the app owns, or an in-memory fake in tests. */
export interface VideoJobStore {
  create(job: VideoJob): Promise<void>;
  get(id: string): Promise<VideoJob | undefined>;
  update(
    id: string,
    patch: Partial<Pick<VideoJob, "status" | "files" | "error">>,
  ): Promise<void>;
}

/** What `getVideoStatus` returns, typed structurally. */
export type VideoStatus =
  | { readonly status: "pending" }
  | {
      readonly status: "succeeded";
      readonly videos: readonly GeneratedFileLike[];
    }
  | { readonly status: "failed"; readonly error?: string };

export interface VideoRoutesOptions {
  readonly model: string;
  readonly files: AiFiles;
  readonly jobs: VideoJobStore;
  readonly authorize: MediaAuthorize;
  readonly quota?: (organizationId: string) => Promise<DbError | undefined>;
  /** Calls `experimental_startVideo` and returns the job reference. */
  readonly start: (args: {
    readonly prompt: string;
    readonly body: Readonly<Record<string, unknown>>;
    readonly model: string;
    readonly jobId: string;
    readonly providerOptions: { readonly gateway: GatewayOptions };
    readonly context: MediaContext;
  }) => PromiseLike<unknown>;
  /** Calls `experimental_getVideoStatus` for one job. */
  readonly status: (providerJob: unknown) => PromiseLike<VideoStatus>;
  /** Runs once when a job finished, such as to meter it. */
  readonly onFinish?: (job: VideoJob) => void | Promise<void>;
}

export interface VideoRoutes {
  /** Starts a job and answers 202 with `{ jobId }`. */
  start(request: Request, context: MediaContext): Promise<Response>;
  /** The owner's poll: answers the job row, asking the provider if pending. */
  poll(jobId: string, context: MediaContext): Promise<Response>;
  /**
   * The provider's webhook. It is an unverified wake-up (the gateway exports no
   * signature verifier), so it only carries a `jobId` and the route asks the
   * provider for the real status. It answers 200 for an unknown job.
   */
  webhook(request: Request): Promise<Response>;
}

/**
 * Routes for a video generation that outlives the request: the job is a row,
 * the finished video is stored in Storage and the row says where.
 */
export function createVideoRoutes(options: VideoRoutesOptions): VideoRoutes {
  const refresh = async (job: VideoJob): Promise<VideoJob> => {
    if (job.status !== "pending") {
      return job;
    }

    const status = await options.status(job.providerJob);

    if (status.status === "pending") {
      return job;
    }

    if (status.status === "failed") {
      const error = status.error ?? "The video failed.";

      await options.jobs.update(job.id, { status: "failed", error });

      return { ...job, status: "failed", error };
    }

    const saved = await saveGeneratedFiles(options.files, status.videos, {
      organizationId: job.organizationId,
      ownerId: job.ownerId,
    });

    if (!saved.ok) {
      return job;
    }

    await options.jobs.update(job.id, {
      status: "succeeded",
      files: saved.data,
    });

    const finished: VideoJob = {
      ...job,
      status: "succeeded",
      files: saved.data,
    };

    try {
      await options.onFinish?.(finished);
    } catch {
      // A sink never changes the result.
    }

    return finished;
  };

  const view = (job: VideoJob) => ({
    jobId: job.id,
    status: job.status,
    ...(job.files === undefined ? {} : { files: job.files }),
    ...(job.error === undefined ? {} : { error: job.error }),
  });

  return {
    async start(request, context) {
      const read = await readPrompt(request);

      if (read instanceof Response) {
        return read;
      }

      const denied = await options.authorize(context, read.body);

      if (denied) {
        return problemResponse(denied);
      }

      const exceeded = await options.quota?.(context.organizationId);

      if (exceeded) {
        return problem429(exceeded);
      }

      const jobId = crypto.randomUUID();

      let providerJob: unknown;

      try {
        providerJob = await options.start({
          prompt: read.prompt,
          body: read.body,
          model: options.model,
          jobId,
          providerOptions: gatewayOptions({
            userId: context.userId,
            organizationId: context.organizationId,
            feature: "video",
          }),
          context,
        });
      } catch (cause) {
        return problemResponse(aiErrorToDbError(cause));
      }

      await options.jobs.create({
        id: jobId,
        organizationId: context.organizationId,
        ownerId: context.userId,
        prompt: read.prompt,
        providerJob,
        status: "pending",
      });

      return Response.json({ jobId }, { status: 202 });
    },

    async poll(jobId, context) {
      const job = await options.jobs.get(jobId);

      if (
        job === undefined ||
        job.ownerId !== context.userId ||
        job.organizationId !== context.organizationId
      ) {
        return problemResponse({
          kind: "not_found",
          message: "No such video job.",
          status: 404,
        });
      }

      try {
        return Response.json(view(await refresh(job)));
      } catch (cause) {
        return problemResponse(aiErrorToDbError(cause));
      }
    },

    async webhook(request) {
      const body = await readJson(request);
      const jobId = isRecord(body) ? body["jobId"] : undefined;

      if (typeof jobId === "string") {
        const job = await options.jobs.get(jobId);

        if (job !== undefined) {
          try {
            await refresh(job);
          } catch {
            // The next poll or webhook retries.
          }
        }
      }

      return new Response(null, { status: 200 });
    },
  };
}
