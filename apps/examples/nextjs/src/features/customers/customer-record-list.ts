import "server-only";
import { recordListServer } from "better-supabase/next";
import { defineRecordList } from "better-supabase/records";

import { customerList } from "@/lib/lists";
import { customerRecord } from "@/lib/supabase/records/customer";
import { bsb } from "@/lib/supabase/server";

/**
 * The customer list with the comment count per row, filled for the whole page
 * in one request. The column is hidden without `comments.read`.
 */
const customerRecordList = defineRecordList(customerRecord, customerList, {
  columns: { comments: "count" },
});

export const customerRecords = recordListServer(bsb, customerRecordList);
