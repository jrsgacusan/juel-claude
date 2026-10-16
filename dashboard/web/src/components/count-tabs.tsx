import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"

export function CountTabs<T extends string>({
  tabs,
  value,
  onChange,
  count,
}: {
  tabs: Array<{ id: T; label: string }>
  value: T
  onChange: (value: T) => void
  count: (value: T) => number
}) {
  return (
    <Tabs
      value={value}
      onValueChange={(next) => onChange(next as T)}
      className="max-w-full min-w-0"
    >
      <div className="max-w-full overflow-x-auto overflow-y-hidden overscroll-x-contain">
        <TabsList>
          {tabs.map((tab) => (
            <TabsTrigger key={tab.id} value={tab.id} className="gap-1.5">
              {tab.label}{" "}
              <span className="text-muted-foreground tabular-nums">
                {count(tab.id)}
              </span>
            </TabsTrigger>
          ))}
        </TabsList>
      </div>
    </Tabs>
  )
}
