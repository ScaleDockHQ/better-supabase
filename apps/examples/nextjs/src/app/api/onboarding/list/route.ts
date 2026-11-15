import { onboardingList } from "@/features/onboarding/onboarding-list";
import { loadOnboardingPage } from "@/features/onboarding/onboarding-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/onboarding/list?q=&status=&program=&sort=&after=`: one page of
 * onboarding runs, searched, filtered and sorted by the enrollments block's
 * page methods.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = onboardingList.parse(request.nextUrl.searchParams);
    const { page } = await loadOnboardingPage(db, tenant, query.value);

    return Response.json(page);
  },
  { requireTenant: true, permission: "enrollments.read" },
);
