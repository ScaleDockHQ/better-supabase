/** One row of the collections overview, as the page and the list route send it. */
export interface CollectionRow {
  readonly id: string;
  readonly name: string;
  readonly description: string | null;
  readonly subjectType: string;
  readonly scope: "user" | "team" | "tenant";
  readonly archived: boolean;
  readonly createdAt: string;
}
