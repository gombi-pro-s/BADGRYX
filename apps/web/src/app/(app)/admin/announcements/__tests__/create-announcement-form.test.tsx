import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CreateAnnouncementForm } from "../create-announcement-form";
import { createAnnouncementAction } from "../actions";

// Mocks the "use server" actions module -- outside Next.js's own compiler,
// a "use server" file is just a plain async function, so this isolates the
// form's own client-side wiring (does it submit the right FormData, does it
// show pending/error state) from the real implementation, which needs a
// live Supabase project to run at all (requireAdmin(), a real insert).
vi.mock("../actions", () => ({
  createAnnouncementAction: vi.fn(),
}));

function fillAndSubmit(title: string, body: string) {
  fireEvent.change(screen.getByLabelText("Title"), { target: { value: title } });
  fireEvent.change(screen.getByLabelText("Body (markdown)"), { target: { value: body } });
  fireEvent.click(screen.getByRole("button", { name: "Create announcement" }));
}

describe("CreateAnnouncementForm", () => {
  beforeEach(() => {
    vi.mocked(createAnnouncementAction).mockReset();
  });

  it("submits the title and body as FormData to the action", async () => {
    vi.mocked(createAnnouncementAction).mockResolvedValue({ error: null });
    render(<CreateAnnouncementForm />);

    fillAndSubmit("New CTF event live", "Details about the event.");

    await waitFor(() => expect(createAnnouncementAction).toHaveBeenCalledTimes(1));
    const formData = vi.mocked(createAnnouncementAction).mock.calls[0][1];
    expect(formData.get("title")).toBe("New CTF event live");
    expect(formData.get("body_markdown")).toBe("Details about the event.");
  });

  it("submits the optional Spanish translation fields as FormData", async () => {
    vi.mocked(createAnnouncementAction).mockResolvedValue({ error: null });
    render(<CreateAnnouncementForm />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "New CTF event live" } });
    fireEvent.change(screen.getByLabelText("Body (markdown)"), { target: { value: "Details about the event." } });
    fireEvent.change(screen.getByLabelText("Title (Spanish)"), { target: { value: "Nuevo evento CTF en vivo" } });
    fireEvent.change(screen.getByLabelText("Body (Spanish, markdown)"), { target: { value: "Detalles..." } });
    fireEvent.click(screen.getByRole("button", { name: "Create announcement" }));

    await waitFor(() => expect(createAnnouncementAction).toHaveBeenCalledTimes(1));
    const formData = vi.mocked(createAnnouncementAction).mock.calls[0][1];
    expect(formData.get("title_es")).toBe("Nuevo evento CTF en vivo");
    expect(formData.get("body_markdown_es")).toBe("Detalles...");
  });

  it("disables the button and shows a pending label while the action is in flight", async () => {
    let resolveAction!: (value: { error: null }) => void;
    vi.mocked(createAnnouncementAction).mockImplementation(
      () => new Promise((resolve) => (resolveAction = resolve)),
    );
    render(<CreateAnnouncementForm />);

    fillAndSubmit("Title", "Body");

    const pendingButton = await screen.findByRole("button", { name: "Creating..." });
    expect(pendingButton).toBeDisabled();

    resolveAction({ error: null });
    await waitFor(() => expect(screen.getByRole("button", { name: "Create announcement" })).not.toBeDisabled());
  });

  it("renders an error returned by the action instead of silently failing", async () => {
    vi.mocked(createAnnouncementAction).mockResolvedValue({ error: "Something went wrong." });
    render(<CreateAnnouncementForm />);

    fillAndSubmit("Title", "Body");

    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong.");
  });
});
