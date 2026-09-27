import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CreatePathForm } from "../create-path-form";
import { createPathAction } from "../actions";

vi.mock("../actions", () => ({
  createPathAction: vi.fn(),
}));

describe("CreatePathForm", () => {
  beforeEach(() => {
    vi.mocked(createPathAction).mockReset();
  });

  it("submits title, slug, and description as FormData", async () => {
    vi.mocked(createPathAction).mockResolvedValue({ error: null });
    render(<CreatePathForm />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Web App Security" } });
    fireEvent.change(screen.getByLabelText("Slug"), { target: { value: "web-app-security" } });
    fireEvent.change(screen.getByLabelText("Description"), { target: { value: "Learn the fundamentals." } });
    fireEvent.click(screen.getByRole("button", { name: "Create path" }));

    await waitFor(() => expect(createPathAction).toHaveBeenCalledTimes(1));
    const formData = vi.mocked(createPathAction).mock.calls[0][1];
    expect(formData.get("title")).toBe("Web App Security");
    expect(formData.get("slug")).toBe("web-app-security");
    expect(formData.get("description")).toBe("Learn the fundamentals.");
  });

  it("renders the slug-collision error the action returns", async () => {
    vi.mocked(createPathAction).mockResolvedValue({ error: "That slug is already in use." });
    render(<CreatePathForm />);

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Dup" } });
    fireEvent.change(screen.getByLabelText("Slug"), { target: { value: "dup" } });
    fireEvent.click(screen.getByRole("button", { name: "Create path" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("That slug is already in use.");
  });
});
