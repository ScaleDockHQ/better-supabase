import { dbError, problemResponse } from "better-supabase";

/**
 * Unknown `/api` paths answer a Problem Details 404. Without this route the
 * `[locale]` root segment would read `api` as a locale and render an HTML 404,
 * because a dynamic root segment matches every path, so Next never reaches
 * `global-not-found.tsx` for them.
 */
function notFound(request: Request): Response {
  return problemResponse(dbError("not_found", "No API route at this path."), {
    instance: new URL(request.url).pathname,
  });
}

export {
  notFound as DELETE,
  notFound as GET,
  notFound as PATCH,
  notFound as POST,
  notFound as PUT,
};
