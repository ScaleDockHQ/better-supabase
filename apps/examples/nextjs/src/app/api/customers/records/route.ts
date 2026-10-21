import { customerRecords } from "../../../../features/customers/customer-record-list";

/**
 * `GET /api/customers/records?q=&status=&sort=&page=`: a page of customers with
 * a comment count per row, the facet counts and the caller's flags.
 * `useCustomerListState().searchParams` builds the query.
 */
export async function GET(request: Request): Promise<Response> {
  const result = await customerRecords.load(new URL(request.url).searchParams);

  if (!result.ok) {
    return Response.json(
      { error: result.error },
      { status: result.error.kind === "validation" ? 400 : 500 },
    );
  }

  return Response.json(result.data);
}
