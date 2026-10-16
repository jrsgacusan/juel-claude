import { Monitor, Moon, Sun } from "lucide-react"
import { type Theme, useTheme } from "@/components/theme-provider"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"

const THEMES = [
  { value: "system", icon: Monitor, label: "System" },
  { value: "light", icon: Sun, label: "Light" },
  { value: "dark", icon: Moon, label: "Dark" },
] as const satisfies ReadonlyArray<{
  value: Theme
  icon: unknown
  label: string
}>

/** System / Light / Dark (star-dashboard-mock.html:349-366), kept in localStorage['star-theme'] by the provider. The selected item is styled from aria-checked: a single toggle group renders radios, and TooltipTrigger's asChild replaces the item's data-state. */
export function ThemeSwitch() {
  const { theme, setTheme } = useTheme()
  return (
    <ToggleGroup
      type="single"
      variant="outline"
      size="sm"
      spacing={0}
      value={theme}
      onValueChange={(value) => {
        if (value) setTheme(value as Theme)
      }}
      aria-label="Theme"
    >
      {THEMES.map(({ value, icon: Icon, label }) => (
        <Tooltip key={value}>
          <TooltipTrigger asChild>
            <ToggleGroupItem
              value={value}
              aria-label={`${label} theme`}
              className="text-muted-foreground pointer-coarse:h-11 pointer-coarse:min-w-11 aria-checked:bg-accent aria-checked:text-foreground aria-checked:shadow-sm"
            >
              <Icon />
              <span className="hidden lg:inline">{label}</span>
            </ToggleGroupItem>
          </TooltipTrigger>
          <TooltipContent>{`${label} theme`}</TooltipContent>
        </Tooltip>
      ))}
    </ToggleGroup>
  )
}
