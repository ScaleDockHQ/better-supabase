/** One row of the reviews overview, as the page and the list route send it. */
export interface ReviewRow {
  readonly id: string;
  readonly title: string | null;
  readonly excerpt: string | null;
  readonly author: string | null;
  readonly rating: number;
  readonly status: "pending" | "published" | "rejected";
  readonly verified: boolean;
  readonly subject: string;
  readonly createdAt: string;
}
