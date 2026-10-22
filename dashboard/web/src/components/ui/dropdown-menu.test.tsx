import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it, vi } from "vitest"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

describe("DropdownMenu", () => {
  it("opens a radio group and closes after a choice", async () => {
    const onValueChange = vi.fn()
    render(
      <DropdownMenu>
        <DropdownMenuTrigger>Theme</DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuRadioGroup value="system" onValueChange={onValueChange}>
            <DropdownMenuRadioItem value="system">System</DropdownMenuRadioItem>
            <DropdownMenuRadioItem value="light">Light</DropdownMenuRadioItem>
            <DropdownMenuRadioItem value="dark">Dark</DropdownMenuRadioItem>
          </DropdownMenuRadioGroup>
        </DropdownMenuContent>
      </DropdownMenu>,
    )
    const user = userEvent.setup()
    await user.click(screen.getByRole("button", { name: "Theme" }))
    expect(screen.getAllByRole("menuitemradio").map((el) => el.textContent)).toEqual(["System", "Light", "Dark"])
    await user.click(screen.getByRole("menuitemradio", { name: "Dark" }))
    expect(onValueChange).toHaveBeenCalledWith("dark")
    expect(screen.queryByRole("menu")).not.toBeInTheDocument()
  })
})
