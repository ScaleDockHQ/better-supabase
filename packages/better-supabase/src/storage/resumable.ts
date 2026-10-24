import { decodeJwtPayload } from "../core/base64.ts";

/** Storage signs upload tokens for two hours. */
const UPLOAD_TOKEN_SECONDS = 7200;

const HOSTED = /^(?<ref>[a-z0-9-]+)\.supabase\.co$/i;

const SIGNED_UPLOAD = "/object/upload/sign/";

const STORAGE_PATH = "/storage/v1";

export interface ResumableEndpointOptions {
  /**
   * On a hosted project, send the upload to the direct Storage host
   * (`<project-ref>.storage.supabase.co`), which Supabase recommends for large
   * files. Defaults to true; other hosts, such as a local stack or a custom
   * domain, are kept.
   */
  readonly direct?: boolean;
}

/**
 * The TUS endpoint for a signed resumable upload,
 * `<storage>/upload/resumable/sign`. `url` is the project URL (`SUPABASE_URL`),
 * the Storage URL (`.../storage/v1`) or a signed upload URL from
 * `createSignedUploadUrl`.
 */
export function resumableEndpoint(
  url: string,
  options: ResumableEndpointOptions = {},
): string {
  const parsed = new URL(url);
  const path = parsed.pathname;
  const storage = path.indexOf(STORAGE_PATH);
  const signed = path.indexOf(SIGNED_UPLOAD);

  const base =
    storage === -1
      ? signed === -1
        ? `${path.replace(/\/+$/, "")}${STORAGE_PATH}`
        : path.slice(0, signed)
      : path.slice(0, storage + STORAGE_PATH.length);

  const hosted = HOSTED.exec(parsed.hostname);

  if ((options.direct ?? true) && hosted?.groups?.["ref"] !== undefined) {
    parsed.hostname = `${hosted.groups["ref"]}.storage.supabase.co`;
  }

  parsed.pathname = `${base}/upload/resumable/sign`;
  parsed.search = "";
  parsed.hash = "";

  return parsed.toString();
}

/** When a signed upload token expires: its `exp`, else two hours from `now`. */
export function uploadTokenExpiry(token: string, now: number): string {
  const exp = decodeJwtPayload(token)?.["exp"];

  const seconds =
    typeof exp === "number" && Number.isFinite(exp)
      ? exp
      : Math.floor(now / 1000) + UPLOAD_TOKEN_SECONDS;

  return new Date(seconds * 1000).toISOString();
}
