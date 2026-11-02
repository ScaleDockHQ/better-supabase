import { createAppraisals } from "better-supabase/blocks/appraisals";

type Transport = Parameters<typeof createAppraisals>[0]["transport"];

/** Creates a cycle with a weighted rubric and rates it per competency. */
export async function rubricCycle(transport: Transport, reviewId: string) {
  const appraisals = createAppraisals({ transport, tenant: "org-1" });

  const cycle = await appraisals.createCycle({
    name: "2031 review",
    startsOn: "2031-01-01",
    endsOn: "2031-03-31",
    competencies: [
      { key: "craft", name: "Craft", weight: 3 },
      { key: "teamwork", name: "Teamwork" },
    ],
  });

  const review = await appraisals.submitReview({
    reviewId,
    input: {
      ratings: [
        { competency: "craft", rating: 4, comment: "Solid reviews" },
        { competency: "teamwork", rating: 3 },
      ],
    },
  });

  return { cycle, review };
}
