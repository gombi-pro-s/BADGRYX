"use client";

import { useTransition } from "react";
import { deleteOrgAnnouncementAction } from "./actions";

export function DeleteOrgAnnouncementButton({
  organizationId,
  announcementId,
}: {
  organizationId: string;
  announcementId: string;
}) {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        if (!confirm("Delete this announcement? This can't be undone.")) return;
        startTransition(() => deleteOrgAnnouncementAction(organizationId, announcementId));
      }}
      className="shrink-0 text-sm font-medium text-danger hover:underline disabled:opacity-50"
    >
      {pending ? "Deleting..." : "Delete"}
    </button>
  );
}
