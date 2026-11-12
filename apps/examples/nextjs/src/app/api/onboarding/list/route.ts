import {
  onboardingList,
  onboardingSpec,
} from "@/features/onboarding/onboarding-list";
import { readOnboardingRows } from "@/features/onboarding/onboarding-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/onboarding/list?q=&status=&program=&sort=&after=`: one page of
 * onboarding runs, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const { rows } = await readOnboardingRows(db, tenant);
    const query = onboardingList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(onboardingList, onboardingSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "enrollments.read" },
);
