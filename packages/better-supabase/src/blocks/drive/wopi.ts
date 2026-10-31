import type { DbError } from "../../core/errors.ts";
import type { Drive, DriveNode } from "./drive.ts";

import { base64ToText, fromBase64, toBase64Url } from "../../core/base64.ts";
import { temporal } from "../../core/temporal-required.ts";

/** The drive methods a WOPI host calls, as the file's user. */
export type WopiDrive = Pick<
  Drive,
  "get" | "lock" | "unlock" | "download" | "uploadRevision" | "commit"
>;

/** What an access token says: one file, one user, and whether it may write. */
export interface WopiTokenClaims {
  readonly fileId: string;
  readonly userId: string;
  /** The name the editor shows for the user. */
  readonly userName?: string;
  readonly canWrite: boolean;
}

export interface WopiHostOptions {
  /** The key that signs access tokens. Keep it server-side. */
  readonly secret: string;
  /**
   * A drive client that acts as `claims.userId` (a client over the user's
   * session, or a service client with `forContext`), so grants, locks and audit
   * apply to that user.
   */
  readonly driveFor: (
    claims: WopiTokenClaims,
  ) => WopiDrive | Promise<WopiDrive>;
  /** The path the host answers under. Default: `/wopi`. */
  readonly prefix?: string;
  /** How long a WOPI lock lasts, in minutes. Default: 30 (the WOPI default). */
  readonly lockMinutes?: number;
  /** The most bytes `PutFile` takes. Default: 100 MiB. */
  readonly maxBytes?: number;
  /** The clock, in epoch milliseconds. For tests. */
  readonly now?: () => number;
}

export interface WopiHost {
  /**
   * Signs the access token for an editor session on one file. The editor sends
   * it back as `access_token` on every call. Returns the token and the epoch
   * milliseconds it stops working (`access_token_ttl`).
   */
  token(
    claims: WopiTokenClaims,
    options?: { readonly ttlSeconds?: number },
  ): Promise<{ readonly accessToken: string; readonly accessTokenTtl: number }>;
  /** Answers a WOPI request; mount it on any route that passes a `Request`. */
  handle(request: Request): Promise<Response>;
}

const LOCK_PREFIX = "wopi:";
const MAX_LOCK_LENGTH = 500 - LOCK_PREFIX.length;
const DEFAULT_TTL_SECONDS = 600;
const DEFAULT_MAX_BYTES = 100 * 1024 * 1024;

interface Signed {
  readonly f: string;
  readonly u: string;
  readonly n?: string;
  readonly w: boolean;
  /** Epoch milliseconds. */
  readonly e: number;
}

const encoder = new TextEncoder();

function importKey(secret: string, usages: ("sign" | "verify")[]) {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages,
  );
}

function isSigned(value: unknown): value is Signed {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  // SAFETY: a non-null object; each field is checked below.
  const v = value as Partial<Record<keyof Signed, unknown>>;

  return (
    typeof v.f === "string" &&
    typeof v.u === "string" &&
    typeof v.w === "boolean" &&
    typeof v.e === "number" &&
    (v.n === undefined || typeof v.n === "string")
  );
}

function reply(
  status: number,
  headers: Record<string, string> = {},
  body: string | ReadableStream<Uint8Array> | null = null,
): Response {
  return new Response(body, { status, headers });
}

function json(body: unknown, headers: Record<string, string> = {}): Response {
  return reply(
    200,
    { "content-type": "application/json", ...headers },
    JSON.stringify(body),
  );
}

/**
 * A live WOPI lock id on the node, `""` for none, `undefined` for a lock WOPI
 * didn't take.
 */
function wopiLock(node: DriveNode, now: number): string | undefined {
  const until = node.lockedUntil;

  if (
    node.lockedBy === undefined ||
    until === undefined ||
    until.epochMilliseconds <= now
  ) {
    return "";
  }

  return node.lockNote?.startsWith(LOCK_PREFIX)
    ? node.lockNote.slice(LOCK_PREFIX.length)
    : undefined;
}

function fromError(error: DbError): Response {
  if (error.hint === "DRIVE_LOCKED") {
    return reply(409, {
      "x-wopi-lock": "",
      "x-wopi-lockfailurereason": error.message,
    });
  }

  if (error.kind === "not_found") {
    return reply(404);
  }

  if (error.kind === "unauthorized" || error.kind === "forbidden") {
    return reply(401);
  }

  return reply(error.status >= 400 && error.status < 600 ? error.status : 500);
}

/**
 * A WOPI host for drive files: `CheckFileInfo`, `GetFile`, `PutFile`, `Lock`,
 * `Unlock`, `RefreshLock`, `GetLock` and `UnlockAndRelock` on the check-out
 * lock. The editor's lock id lives in the node's `lockNote`, so the same lock
 * stops other drive writers while the document is open.
 */
export function createWopiHost(options: WopiHostOptions): WopiHost {
  const prefix = (options.prefix ?? "/wopi").replace(/\/$/, "");
  const lockMs = (options.lockMinutes ?? 30) * 60_000;
  const maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
  const clock = options.now ?? Date.now;

  async function sign(payload: string): Promise<string> {
    const key = await importKey(options.secret, ["sign"]);
    const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));

    return toBase64Url(new Uint8Array(mac));
  }

  async function verify(
    token: string,
    fileId: string,
  ): Promise<WopiTokenClaims | undefined> {
    const [payload, mac, extra] = token.split(".");

    if (!payload || !mac || extra !== undefined) {
      return undefined;
    }

    try {
      const key = await importKey(options.secret, ["verify"]);

      const valid = await crypto.subtle.verify(
        "HMAC",
        key,
        fromBase64(mac),
        encoder.encode(payload),
      );

      if (!valid) {
        return undefined;
      }

      const parsed: unknown = JSON.parse(base64ToText(payload));

      if (!isSigned(parsed) || parsed.e <= clock() || parsed.f !== fileId) {
        return undefined;
      }

      return {
        fileId: parsed.f,
        userId: parsed.u,
        ...(parsed.n === undefined ? {} : { userName: parsed.n }),
        canWrite: parsed.w,
      };
    } catch {
      return undefined;
    }
  }

  async function token(
    claims: WopiTokenClaims,
    tokenOptions: { readonly ttlSeconds?: number } = {},
  ) {
    const expires =
      clock() + (tokenOptions.ttlSeconds ?? DEFAULT_TTL_SECONDS) * 1000;

    const body: Signed = {
      f: claims.fileId,
      u: claims.userId,
      ...(claims.userName === undefined ? {} : { n: claims.userName }),
      w: claims.canWrite,
      e: expires,
    };

    const payload = toBase64Url(JSON.stringify(body));

    return {
      accessToken: `${payload}.${await sign(payload)}`,
      accessTokenTtl: expires,
    };
  }

  const infoOf = (node: DriveNode, claims: WopiTokenClaims) => ({
    BaseFileName: node.name,
    OwnerId: node.createdBy ?? "",
    Size: node.file?.size ?? 0,
    UserId: claims.userId,
    UserFriendlyName: claims.userName ?? claims.userId,
    Version: node.attachmentId ?? "",
    UserCanWrite: claims.canWrite && !node.readOnly,
    ReadOnly: !claims.canWrite || node.readOnly,
    SupportsLocks: true,
    SupportsGetLock: true,
    SupportsUpdate: true,
    SupportsDeleteFile: false,
    SupportsRename: false,
    UserCanNotWriteRelative: true,
    DisablePrint: node.downloadable === false,
    HidePrintOption: node.downloadable === false,
  });

  const version = (node: DriveNode) => ({
    "x-wopi-itemversion": node.attachmentId ?? "",
  });

  async function getFile(drive: WopiDrive, id: string): Promise<Response> {
    const download = await drive.download(id);

    if (!download.ok) {
      return fromError(download.error);
    }

    const source = await fetch(download.data.signedUrl);

    if (!source.ok) {
      return reply(404);
    }

    const node = await drive.get(id);

    return reply(
      200,
      {
        "content-type": download.data.attachment.mimeType,
        ...(node.ok ? version(node.data) : {}),
      },
      source.body,
    );
  }

  async function putFile(
    drive: WopiDrive,
    claims: WopiTokenClaims,
    request: Request,
  ): Promise<Response> {
    if (!claims.canWrite) {
      return reply(401);
    }

    const node = await drive.get(claims.fileId);

    if (!node.ok) {
      return fromError(node.error);
    }

    const current = wopiLock(node.data, clock());
    const requested = request.headers.get("x-wopi-lock") ?? "";

    // WOPI: an unlocked file takes a PutFile only while it is empty.
    if (
      current === undefined ||
      requested !== current ||
      (current === "" && (node.data.file?.size ?? 0) > 0)
    ) {
      return reply(409, { "x-wopi-lock": current ?? "" });
    }

    const body = await request.arrayBuffer();

    if (body.byteLength > maxBytes) {
      return reply(413);
    }

    const mimeType = node.data.file?.mimeType ?? "application/octet-stream";

    const upload = await drive.uploadRevision(claims.fileId, {
      mimeType,
      size: body.byteLength,
    });

    if (!upload.ok) {
      return fromError(upload.error);
    }

    const stored = await fetch(upload.data.signedUrl, {
      method: "PUT",
      headers: { "content-type": mimeType },
      body,
    });

    if (!stored.ok) {
      return reply(500);
    }

    const committed = await drive.commit(
      claims.fileId,
      upload.data.attachment.id,
    );

    return committed.ok
      ? reply(200, version(committed.data))
      : fromError(committed.error);
  }

  async function lockOp(
    drive: WopiDrive,
    claims: WopiTokenClaims,
    override: string,
    request: Request,
  ): Promise<Response> {
    const node = await drive.get(claims.fileId);

    if (!node.ok) {
      return fromError(node.error);
    }

    const current = wopiLock(node.data, clock());
    const lockId = request.headers.get("x-wopi-lock") ?? "";
    const oldLock = request.headers.get("x-wopi-oldlock") ?? "";

    const mismatch = (): Response =>
      reply(409, { "x-wopi-lock": current ?? "" });

    if (override === "GET_LOCK") {
      return reply(200, { "x-wopi-lock": current ?? "" });
    }

    if (!claims.canWrite) {
      return reply(401);
    }

    if (lockId.length === 0 || lockId.length > MAX_LOCK_LENGTH) {
      return reply(400);
    }

    const take = async (): Promise<Response> => {
      const locked = await drive.lock(claims.fileId, {
        until: temporal().Instant.fromEpochMilliseconds(clock() + lockMs),
        note: `${LOCK_PREFIX}${lockId}`,
      });

      return locked.ok
        ? reply(200, version(locked.data))
        : fromError(locked.error);
    };

    switch (override) {
      case "LOCK": {
        return current === "" || current === lockId ? take() : mismatch();
      }

      case "REFRESH_LOCK": {
        return current !== "" && current === lockId ? take() : mismatch();
      }

      case "UNLOCK": {
        if (current === undefined || current !== lockId || current === "") {
          return mismatch();
        }

        const unlocked = await drive.unlock(claims.fileId);

        return unlocked.ok
          ? reply(200, version(unlocked.data))
          : fromError(unlocked.error);
      }

      case "UNLOCK_AND_RELOCK": {
        return current !== undefined && current !== "" && current === oldLock
          ? take()
          : mismatch();
      }

      default: {
        return reply(501);
      }
    }
  }

  async function handle(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (!url.pathname.startsWith(`${prefix}/files/`)) {
      return reply(404);
    }

    const [id, tail, ...rest] = url.pathname
      .slice(prefix.length + "/files/".length)
      .split("/");

    if (!id || rest.length > 0 || (tail !== undefined && tail !== "contents")) {
      return reply(404);
    }

    const accessToken = url.searchParams.get("access_token") ?? "";
    const claims = await verify(accessToken, decodeURIComponent(id));

    if (!claims) {
      return reply(401);
    }

    const drive = await options.driveFor(claims);
    const override = request.headers.get("x-wopi-override");

    if (tail === "contents") {
      if (request.method === "GET") {
        return getFile(drive, claims.fileId);
      }

      return request.method === "POST"
        ? putFile(drive, claims, request)
        : reply(405);
    }

    if (request.method === "GET") {
      const node = await drive.get(claims.fileId);

      return node.ok ? json(infoOf(node.data, claims)) : fromError(node.error);
    }

    if (request.method === "POST" && override) {
      return lockOp(drive, claims, override, request);
    }

    return reply(request.method === "POST" ? 501 : 405);
  }

  return { token, handle };
}
