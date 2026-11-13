import type { RecordBinding } from "../record-bindings.ts";
import type { Leave, LeaveRequest } from "./leave.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The leave requests of an employee, or of a member when the subject is not an
 * employee, earliest first. It reads through `leave.forOwner`, which takes the
 * organization from the block's `tenant` option; the employee filter needs the
 * employees block or `owner: "employee"`. Requesting or deciding leave takes
 * dates and an approval, so the binding has no writes.
 */
export const leaveBinding: RecordBinding<Leave, readonly LeaveRequest[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "leave",
    load: (client: Leave, subject) => client.forOwner({ subject }),
    events: ["leave_request.*"],
  });
