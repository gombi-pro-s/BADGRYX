import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EditAnnouncementForm } from "../edit-announcement-form";
import { updateAnnouncementAction } from "../actions";

vi.mock("../actions", () => ({
  updateAnnouncementAction: vi.fn(),
}));

const initial = {
  title: "Original title",
  body_markdown: "Original body",
  expires_at: null,
  title_es: null,
  body_markdown_es: null,
};

describe("EditAnnouncementForm", () => {
  beforeEach(() => {
    vi.mocked(updateAnnouncementAction).mockReset();
  });

  it("pre-fills the fields from the initial values", () => {
    render(<EditAnnouncementForm announcementId="a1" initial={initial} />);
    expect(screen.getByLabelText("Title")).toHaveValue("Original title");
    expect(screen.getByLabelText("Body (markdown)")).toHaveValue("Original body");
  });

  it("calls updateAnnouncementAction bound to this announcement's id, with the edited FormData", async () => {
    vi.mocked(updateAnnouncementAction).mockResolvedValue({ error: null });
    render(<EditAnnouncementForm announcementId="a1" initial={initial} />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Edited title" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    // .bind(null, announcementId) makes announcementId the action's first
    // arg, then React supplies (prevState, formData) as the next two --
    // asserting all three proves the id-binding wiring, not just the form.
    await waitFor(() => expect(updateAnnouncementAction).toHaveBeenCalledTimes(1));
    const call = vi.mocked(updateAnnouncementAction).mock.calls[0];
    expect(call[0]).toBe("a1");
    const formData = call[2];
    expect(formData.get("title")).toBe("Edited title");
    expect(formData.get("body_markdown")).toBe("Original body");
  });

  it("pre-fills the Spanish translation fields when one exists", () => {
    render(
      <EditAnnouncementForm
        announcementId="a1"
        initial={{ ...initial, title_es: "Título original", body_markdown_es: "Cuerpo original" }}
      />,
    );
    expect(screen.getByLabelText("Title (Spanish)")).toHaveValue("Título original");
    expect(screen.getByLabelText("Body (Spanish, markdown)")).toHaveValue("Cuerpo original");
  });

  it("submits cleared Spanish fields as empty strings, so the server can remove the translation", async () => {
    vi.mocked(updateAnnouncementAction).mockResolvedValue({ error: null });
    render(
      <EditAnnouncementForm
        announcementId="a1"
        initial={{ ...initial, title_es: "Título original", body_markdown_es: "Cuerpo original" }}
      />,
    );

    fireEvent.change(screen.getByLabelText("Title (Spanish)"), { target: { value: "" } });
    fireEvent.change(screen.getByLabelText("Body (Spanish, markdown)"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(updateAnnouncementAction).toHaveBeenCalledTimes(1));
    const formData = vi.mocked(updateAnnouncementAction).mock.calls[0][2];
    expect(formData.get("title_es")).toBe("");
    expect(formData.get("body_markdown_es")).toBe("");
  });

  it("renders an error returned by the action", async () => {
    vi.mocked(updateAnnouncementAction).mockResolvedValue({ error: "That slug is already in use." });
    render(<EditAnnouncementForm announcementId="a1" initial={initial} />);

    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("That slug is already in use.");
  });
});
