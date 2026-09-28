import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CreateOrgAnnouncementForm } from "../create-announcement-form";
import { createOrgAnnouncementAction } from "../actions";

vi.mock("../actions", () => ({
  createOrgAnnouncementAction: vi.fn(),
}));

describe("CreateOrgAnnouncementForm", () => {
  beforeEach(() => {
    vi.mocked(createOrgAnnouncementAction).mockReset();
  });

  it("calls createOrgAnnouncementAction bound to this organization's id", async () => {
    vi.mocked(createOrgAnnouncementAction).mockResolvedValue({ error: null });
    render(<CreateOrgAnnouncementForm organizationId="org-1" />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Lab maintenance tonight" } });
    fireEvent.change(screen.getByLabelText("Body (markdown)"), { target: { value: "9pm-10pm UTC." } });
    fireEvent.click(screen.getByRole("button", { name: "Post announcement" }));

    await waitFor(() => expect(createOrgAnnouncementAction).toHaveBeenCalledTimes(1));
    const call = vi.mocked(createOrgAnnouncementAction).mock.calls[0];
    expect(call[0]).toBe("org-1");
    const formData = call[2];
    expect(formData.get("title")).toBe("Lab maintenance tonight");
    expect(formData.get("body_markdown")).toBe("9pm-10pm UTC.");
  });

  it("submits the optional Spanish translation fields as FormData", async () => {
    vi.mocked(createOrgAnnouncementAction).mockResolvedValue({ error: null });
    render(<CreateOrgAnnouncementForm organizationId="org-1" />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Lab maintenance tonight" } });
    fireEvent.change(screen.getByLabelText("Body (markdown)"), { target: { value: "9pm-10pm UTC." } });
    fireEvent.change(screen.getByLabelText("Title (Spanish)"), { target: { value: "Mantenimiento esta noche" } });
    fireEvent.change(screen.getByLabelText("Body (Spanish, markdown)"), { target: { value: "9pm-10pm UTC." } });
    fireEvent.click(screen.getByRole("button", { name: "Post announcement" }));

    await waitFor(() => expect(createOrgAnnouncementAction).toHaveBeenCalledTimes(1));
    const formData = vi.mocked(createOrgAnnouncementAction).mock.calls[0][2];
    expect(formData.get("title_es")).toBe("Mantenimiento esta noche");
    expect(formData.get("body_markdown_es")).toBe("9pm-10pm UTC.");
  });

  it("renders an error returned by the action", async () => {
    vi.mocked(createOrgAnnouncementAction).mockResolvedValue({ error: "Invalid input." });
    render(<CreateOrgAnnouncementForm organizationId="org-1" />);
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "T" } });
    fireEvent.change(screen.getByLabelText("Body (markdown)"), { target: { value: "B" } });
    fireEvent.click(screen.getByRole("button", { name: "Post announcement" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Invalid input.");
  });
});
