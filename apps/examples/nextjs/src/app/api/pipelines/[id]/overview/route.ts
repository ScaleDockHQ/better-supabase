import { pipelineOverview } from "../../../../../lib/read-sets";
import { bsbCore as bsb } from "../../../../../lib/supabase/server-core";

/**
 * `GET /api/pipelines/:id/overview`: the pipeline board and the customer count
 * in one round trip, from the `pipeline_overview` read set.
 */
export const GET = bsb.route<{ id: string }>((_request, { db, params }) =>
  db.$many(pipelineOverview, { pipelineId: params.id }),
);
