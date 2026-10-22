"use client";

import { useAction } from "better-supabase/react";
import { CheckIcon, GraduationCapIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  completeLesson,
  createSampleCourse,
  enrollInCourse,
} from "../courses-actions";

export function EnrollButton({ courseId }: { courseId: string }) {
  const t = useExtracted("courses");
  const message = useErrorMessage();

  const enroll = useAction(enrollInCourse, {
    onSuccess: () => {
      toast.success(t("You're enrolled"));
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      disabled={enroll.pending}
      onClick={() => {
        void enroll.run({ courseId });
      }}
    >
      <GraduationCapIcon />
      {t("Enroll")}
    </Button>
  );
}

export function CompleteLessonButton({ lessonId }: { lessonId: string }) {
  const t = useExtracted("courses");
  const message = useErrorMessage();

  const complete = useAction(completeLesson, {
    onSuccess: (data) => {
      toast.success(
        data.status === "completed"
          ? t("Course completed")
          : t("Lesson marked done"),
      );
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      disabled={complete.pending}
      onClick={() => {
        void complete.run({ lessonId });
      }}
    >
      <CheckIcon />
      {t("Mark as done")}
    </Button>
  );
}

/** Creates a published sample course and opens its outline. */
export function SampleCourseButton() {
  const t = useExtracted("courses");
  const message = useErrorMessage();
  const router = useRouter();

  const create = useAction(createSampleCourse, {
    onSuccess: (data) => {
      router.push(`/courses/${data.id}`);
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      disabled={create.pending}
      onClick={() => {
        void create.run({
          title: t("Getting started"),
          lessons: [
            {
              title: t("Welcome"),
              text: t(
                "This lesson shows how a learner moves through a course.",
              ),
            },
            {
              title: t("Next steps"),
              text: t("Mark this lesson done to complete the course."),
            },
          ],
        });
      }}
    >
      <PlusIcon />
      {t("Create a sample course")}
    </Button>
  );
}
