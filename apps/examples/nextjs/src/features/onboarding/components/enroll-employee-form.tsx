"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";

import { enrollEmployee } from "../onboarding-actions";

interface Option {
  readonly value: string;
  readonly label: string;
}

/** Starts one employee on one program. */
export function EnrollEmployeeForm({
  programs,
  employees,
}: {
  programs: readonly Option[];
  employees: readonly Option[];
}) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();
  const [program, setProgram] = useState<string | null>(null);
  const [employeeId, setEmployeeId] = useState<string | null>(null);

  const enroll = useAction(enrollEmployee, {
    onSuccess: () => {
      toast.success(t("Employee enrolled"));
      setEmployeeId(null);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select value={program} onValueChange={setProgram} items={programs}>
        <SelectTrigger className="w-48" aria-label={t("Program")}>
          <SelectValue placeholder={t("Program")} />
        </SelectTrigger>
        <SelectContent>
          {programs.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Select
        value={employeeId}
        onValueChange={setEmployeeId}
        items={employees}
      >
        <SelectTrigger className="w-56" aria-label={t("Employee")}>
          <SelectValue placeholder={t("Employee")} />
        </SelectTrigger>
        <SelectContent>
          {employees.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button
        disabled={enroll.pending || program === null || employeeId === null}
        onClick={() => {
          if (program !== null && employeeId !== null) {
            void enroll.run({ program, employeeId });
          }
        }}
      >
        {t("Enroll")}
      </Button>
    </div>
  );
}
