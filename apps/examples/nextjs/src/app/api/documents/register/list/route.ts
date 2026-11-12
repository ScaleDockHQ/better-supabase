import {
  registerList,
  registerSpec,
} from "@/features/document-register/document-register-list";
import { readRegisterRows } from "@/features/document-register/document-register-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/documents/register/list?q=&type=&status=&review=&sort=&after=`: one
 * page of controlled documents, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const rows = await readRegisterRows(db, tenant);
    const query = registerList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(registerList, registerSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "drive.read" },
);
