"use client";

import { useTransition } from "react";
import { deleteAnnouncementAction } from "./actions";

export function DeleteAnnouncementButton({ announcementId }: { announcementId: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        if (!confirm("Delete this announcement? This can't be undone.")) return;
        startTransition(() => deleteAnnouncementAction(announcementId));
      }}
      className="shrink-0 text-sm font-medium text-danger hover:underline disabled:opacity-50"
    >
      {pending ? "Deleting..." : "Delete"}
    </button>
  );
}
