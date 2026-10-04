import type { SupportApi } from "./support.ts";

import { clearSupportCookie } from "../auth/support-cookie.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";

const NOT_CONFIGURED =
  "Support sessions need createServer(betterSupabase, { support: supportSessions({ store }) })";

const notConfigured = <T>(): AsyncResult<T> =>
  AsyncResult.err<T>(dbError("unexpected", NOT_CONFIGURED));

/** `bs.support` without `ServerOptions.support`: every call fails. */
export const supportOff: SupportApi = {
  start: notConfigured,
  stop: notConfigured,
  revoke: notConfigured,
  current: () => Promise.resolve(undefined),
  list: notConfigured,
  sessionIdOf: () => undefined,
  clearCookie: () => clearSupportCookie(),
};
