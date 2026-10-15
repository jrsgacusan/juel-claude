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

/** System / Light / Dark (star-dashboard-mock.html:349-366), kept in localStorage['star-theme'] by the provider. */
export function ThemeSwitch() {
  const { theme, setTheme } = useTheme()
  return (
    <ToggleGroup
      type="single"
      variant="outline"
      size="sm"
      value={theme}
      onValueChange={(value) => {
        if (value) setTheme(value as Theme)
      }}
      aria-label="Theme"
    >
      {THEMES.map(({ value, icon: Icon, label }) => (
        <Tooltip key={value}>
          <TooltipTrigger asChild>
            <ToggleGroupItem value={value} aria-label={`${label} theme`}>
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
