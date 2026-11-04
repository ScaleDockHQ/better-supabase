import type { RequestContext } from "../core/plugin.ts";
import type { StatsRecorder } from "../core/stats.ts";

import { formatStats } from "./collector.ts";

/** Options of `bsb.admin()`; `request` attaches the calls to that render. */
export interface RequestAdminOptions {
  readonly as?: string;
  readonly stats?: StatsRecorder;
  readonly request?: Request;
}

/** The `onVerify` option that counts a real token verification, if recording. */
export const verifyOption = (
  recorder: StatsRecorder | undefined,
): { readonly onVerify?: () => void } =>
  recorder
    ? {
        onVerify: () => {
          recorder.verification();
        },
      }
    : {};

/** Sets the stats header from a recorder's totals so far. */
export const stampStats = (
  headers: Headers,
  name: string,
  recorder: StatsRecorder | undefined,
): void => {
  if (recorder) {
    headers.set(name, formatStats(recorder.snapshot()));
  }
};

/** Wraps the admin factory so `{ request }` resolves to that render's recorder. */
export const adminForRequest =
  <T>(
    admin: (
      context?: RequestContext,
      options?: Omit<RequestAdminOptions, "request">,
    ) => T,
    recorderOf: (request: Request) => StatsRecorder | undefined,
  ) =>
  (context?: RequestContext, options?: RequestAdminOptions): T => {
    const { request, ...rest } = options ?? {};
    const stats = request ? recorderOf(request) : undefined;

    return admin(context, {
      ...rest,
      ...(stats && !rest.stats ? { stats } : {}),
    });
  };
