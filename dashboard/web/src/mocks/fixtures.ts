import { paths } from "@/api/paths"
import type {
  Briefing,
  BriefingSummary,
  EvidenceDetail,
  EvidenceRecord,
  FileKind,
  ItemDetail,
  ItemStatus,
  Loop,
  LoopOption,
  Overview,
  Project,
  SearchResult,
  SlackState,
  Tracker,
  TrackerInfo,
} from "@/api/types"

// Sample data for the mock layer in the API's shapes. None of it is real. Times are relative to
// when the db is built (load or resetMockState), so a 12m-old fixture reads 12m on any day.

export const HOME = "sphere-app"
const MINUTE = 60_000

export const ago = (minutes: number): string =>
  new Date(Date.now() - minutes * MINUTE).toISOString()
const slackTs = (minutes: number): string =>
  ((Date.now() - minutes * MINUTE) / 1000).toFixed(6)
const today = () => new Date().toISOString().slice(0, 10)

export type MockBriefing = { summary: BriefingSummary; briefing: Briefing }
export type MockDb = {
  projects: Project[]
  overview: Record<string, Overview>
  loops: Record<string, Loop[]>
  items: Record<string, ItemDetail[]>
  evidence: Record<string, EvidenceDetail[]>
  /** File bodies by "<project>/<path inside the STAR folder>". */
  files: Record<string, { type: string; body: string }>
  slack: SlackState
  briefings: Record<string, MockBriefing[]>
  trackers: Record<string, TrackerInfo>
  trackerConnected: Record<string, Partial<Record<Tracker, boolean>>>
  search: SearchResult[]
}

const opt = (
  label: string,
  answer: string,
  recommended = false
): LoopOption => ({ label, answer, recommended })

type ItemSeed = {
  ref: string
  title: string
  status: ItemStatus
  state: string
  stage: string
  branch: string
  pr?: number
  steps: Array<[minutesAgo: number, text: string]>
  criteria?: string[]
  decisions?: string[]
}

function item(p: string, s: ItemSeed): ItemDetail {
  const [lastAgo, lastText] = s.steps[s.steps.length - 1] ?? [0, ""]
  const lower = lastText.toLowerCase()
  const token = lower.includes("codex gate")
    ? "gate-r2"
    : lower.includes("executor")
      ? "executor"
      : lower.includes("plan")
        ? "phase1"
        : lower.includes("merge")
          ? "phase4"
          : "update"
  return {
    row: {
      item: s.ref,
      ref: s.ref,
      state: s.state,
      stage: s.stage,
      worktree: s.branch ? `.worktrees/${p}/${s.ref.toLowerCase()}` : "-",
      pr: s.pr ? String(s.pr) : "-",
      head: null,
      updated: ago(lastAgo),
      title: s.title,
      status: s.status,
      step: `${token} ${lastText}`,
      prUrl: s.pr ? `https://github.com/example/${p}/pull/${s.pr}` : null,
    },
    progress: s.steps.map(([m, text]) => ({ time: ago(m), text })),
    criteria: s.criteria ?? [],
    decisions: s.decisions ?? [],
  }
}

const emptyOverview = (): Overview => ({
  resume: { state: null, pools: null, next: null, lastTick: null },
  counts: {},
  workers: { brief: [0, 4], build: [0, 3], babysit: [0, 3] },
  gateDown: null,
  away: null,
  awayPending: null,
  quietHours: null,
})

type FileSeed = [name: string, kind: FileKind, text?: string]

function evidence(
  p: string,
  db: Pick<MockDb, "files">,
  s: {
    ref: string
    title: string
    pr: string
    sha: string
    mergedAgo: number
    goAgo: number
    record: EvidenceRecord
    groups: Array<[criterion: string | null, files: FileSeed[]]>
  }
): EvidenceDetail {
  return {
    item: s.ref,
    title: s.title,
    pr: s.pr,
    sha: s.sha,
    mergedAt: ago(s.mergedAgo),
    goAt: ago(s.goAgo),
    record: s.record,
    groups: s.groups.map(([criterion, files]) => ({
      criterion,
      files: files.map(([name, kind, text]) => {
        const path = `evidence/${s.ref}/${name}`
        if (text !== undefined)
          db.files[`${p}/${path}`] = {
            type: "text/plain; charset=utf-8",
            body: text,
          }
        return { name, kind, url: paths.file(p, path) }
      }),
    })),
  }
}

export function createDb(): MockDb {
  const files: MockDb["files"] = {}
  const ria = slackTs(3)
  const marco = slackTs(25)
  const lea = slackTs(60)
  const riaId = `C0SPHERE-${ria}`
  const marcoId = `D0MARCO-${marco}`
  const leaId = `C0RELEASES-${lea}`
  const draft = (id: string) => `drafts/${today()}-${HOME}-slack-${id}.md`
  const replies: Array<
    [id: string, channelId: string, ts: string, reply: string]
  > = [
    [
      riaId,
      "C0SPHERE",
      ria,
      "Not today. It's in final review now, and I expect it merged tomorrow morning, before the demo.",
    ],
    [
      marcoId,
      "D0MARCO",
      marco,
      "Yes, it's mine (SPH-12). I'll share the new copy here before it ships.",
    ],
    [
      leaId,
      "C0RELEASES",
      lea,
      "None yet. It's SPH-13, being built now. I'll post the PR here once it's open.",
    ],
  ]
  for (const [id, channelId, ts, reply] of replies) {
    files[`${HOME}/${draft(id)}`] = {
      type: "text/markdown; charset=utf-8",
      body: `to: slack ${channelId} ${ts}\n${reply}`,
    }
  }
  const slackLoop = (
    id: string,
    minutes: number,
    from: string,
    channel: string,
    text: string,
    msgId: string,
    reply: string
  ): Loop => ({
    id,
    kind: "slack-reply",
    item: "slack",
    title: `${from} in ${channel}: ${text.slice(0, 60)}`,
    body: [
      `draft: ${draft(msgId)}`,
      `message: https://example.slack.com/archives/${msgId.split("-")[0]}/p${msgId.split("-")[1]?.replace(".", "")}`,
    ],
    options: [
      opt("Send the draft", "send", true),
      opt("Make it shorter", "rewrite: shorter"),
      opt("Skip", "skip"),
    ],
    suggestion: `Send: "${reply}"`,
    answer: "",
    askedAt: ago(minutes),
  })

  const db: MockDb = {
    files,
    projects: [
      {
        name: "sphere-app",
        repo: "/Users/owner/code/sphere-app",
        state: "running",
        terminal: "term_sphere_app",
        lastTick: ago(2),
        needsYou: 0,
      },
      {
        name: "sphere-api",
        repo: "/Users/owner/code/sphere-api",
        state: "idle",
        terminal: "term_sphere_api",
        lastTick: ago(30),
        needsYou: 0,
      },
      {
        name: "juel-claude",
        repo: "/Users/owner/code/juel-claude",
        state: "stopped",
        terminal: null,
        lastTick: ago(600),
        needsYou: 0,
      },
    ],
    overview: {
      "sphere-app": {
        resume: {
          state: "running",
          pools: "brief 1/4, build 3/3, babysit 1/3",
          next: "Next tick in 3 min",
          lastTick: ago(2),
        },
        counts: {
          "needs-you": 2,
          stopped: 1,
          building: 2,
          "in-review": 1,
          briefing: 1,
          queued: 2,
          merged: 2,
        },
        workers: { brief: [1, 4], build: [3, 3], babysit: [1, 3] },
        gateDown: null,
        away: null,
        awayPending: null,
        quietHours: { tz: "Asia/Manila", start: "22:00", end: "07:00" },
      },
      "sphere-api": emptyOverview(),
      "juel-claude": emptyOverview(),
    },
    loops: {
      "sphere-app": [
        {
          id: "N-38",
          kind: "escalation",
          item: "SPH-7",
          title: "The merge gate failed twice on e3f1a92",
          body: [
            "e2e / reports-export failed on both runs, in the same test. Babysit fixed one cause, and the second run failed the same way.",
          ],
          options: [
            opt(
              "Run the build again",
              "run the build again: fix e2e / reports-export first",
              true
            ),
            opt("Drop SPH-7", "drop"),
          ],
          suggestion:
            "Run the build again and have it fix that e2e test first. Both failures point at a selector, not at the product.",
          answer: "",
          askedAt: ago(41),
        },
        {
          id: "N-41",
          kind: "go-batch",
          item: "batch-3",
          title: "Start building SPH-11, SPH-12 and SPH-14",
          body: [
            "SPH-11",
            "SPH-12",
            "SPH-14",
            "Options: go / go except <items> / drop <item> / or say what to change",
          ],
          options: [
            opt("Go", "go", true),
            opt("Go, except SPH-14", "go except SPH-14"),
            opt("Drop SPH-12", "drop SPH-12"),
          ],
          suggestion:
            "Go. SPH-11 and SPH-12 start in the next tick. SPH-14 starts on its own once the webhook secret is in.",
          answer: "",
          askedAt: ago(12),
        },
        {
          id: "N-44",
          kind: "person",
          item: "SPH-14",
          title: "Add STRIPE_WEBHOOK_SECRET to .env.local",
          body: [
            "Put the test-mode signing secret in .env.local in the main checkout. The build copies it into its worktree. Never paste the secret here: this page and the queue are plain files.",
          ],
          options: [opt("Done", "done", true), opt("Can't now", "can't now")],
          suggestion:
            "Do it now. SPH-14 is the only item in the batch still waiting on you.",
          answer: "",
          askedAt: ago(12),
        },
        {
          id: "N-43",
          kind: "question",
          item: "SPH-9",
          title:
            "Removing the old export needs a public API change. Widen the scope?",
          body: [
            "The brief keeps the public API out of scope, but /v1/reports/export still serves the old modal, and two clients outside this repo call it.",
            "Suggest: Yes, with a 301 to /v2/reports/export. docs/api.md:41 already marks v1 as deprecated, so both clients keep working.",
          ],
          options: [
            opt(
              "Yes, redirect with a 301",
              "yes, redirect /v1/reports/export to v2 with a 301",
              true
            ),
            opt(
              "No, keep the old route",
              "no, keep /v1/reports/export as it is"
            ),
          ],
          suggestion:
            "Yes, with a 301 to /v2/reports/export. docs/api.md:41 already marks v1 as deprecated, so both clients keep working.",
          answer: "",
          askedAt: ago(6),
        },
        slackLoop(
          "N-48",
          60,
          "Lea",
          "#releases",
          "which PR fixes the invoice time zone?",
          leaId,
          replies[2]?.[3] ?? ""
        ),
        slackLoop(
          "N-47",
          25,
          "Marco",
          "a DM",
          "can you look at the invite email copy before it goes out?",
          marcoId,
          replies[1]?.[3] ?? ""
        ),
        slackLoop(
          "N-45",
          3,
          "Ria",
          "#sphere-eng",
          "hey, is the CSV export landing today? sales wants to demo it tomorrow",
          riaId,
          replies[0]?.[3] ?? ""
        ),
        {
          id: "N-39",
          kind: "waiting",
          item: "SPH-5",
          title: "SPH-5 needs an approval from a teammate",
          body: [
            "SPH-5 passed every gate on 4c19d0e. GitHub does not let you approve your own PR, so it waits for someone else.",
          ],
          options: [opt("Done, I asked", "done")],
          suggestion:
            "Ask in #sphere-eng. STAR merges it within a tick of the approval.",
          answer: "",
          askedAt: null,
        },
        {
          id: "N-46",
          kind: "held",
          item: "SPH-10",
          title:
            "Mark PR #211 ready once quiet hours end, then ask Greptile for its second pass on the same head and post what it finds in #sphere-eng",
          body: [],
          options: [],
          suggestion: null,
          answer: "",
          askedAt: ago(15),
        },
      ],
      "sphere-api": [],
      "juel-claude": [
        {
          id: "N-7",
          kind: "go-merge",
          item: "star-dashboard-server",
          title: "merge PR #131 under a go?",
          body: ["https://github.com/example/juel-claude/pull/131"],
          options: [opt("Go", "go", true), opt("Not merging", "not merging")],
          suggestion: "Go. Every gate passed on 9f3c2e1.",
          answer: "",
          askedAt: ago(30),
        },
      ],
    },
    items: {
      "sphere-app": [
        item(HOME, {
          ref: "SPH-7",
          title: "Keyboard focus on the export button",
          status: "stopped",
          state: "escalated",
          stage: "babysit",
          branch: "fix/sph-7-export-focus",
          pr: 209,
          steps: [
            [180, "Build finished, draft PR #209"],
            [161, "Codex gate passed on round 1"],
            [152, "Marked ready, approved"],
            [41, "Merge gate: e2e / reports-export failed twice"],
          ],
          criteria: [
            "The export button takes keyboard focus after a filter change",
          ],
        }),
        item(HOME, {
          ref: "SPH-9",
          title: "Remove the old export modal",
          status: "needs-you",
          state: "building",
          stage: "build",
          branch: "feat/sph-9-remove-export-modal",
          pr: 213,
          steps: [
            [50, "Plan written, 4 tasks"],
            [31, "Executor done, 6 files changed"],
            [4, "Asked: widen the scope to the public API?"],
          ],
          criteria: [
            "The old export modal is gone",
            "Export opens the new export page",
          ],
          decisions: ["D1 Keep /v1/reports/export until both clients move"],
        }),
        item(HOME, {
          ref: "SPH-5",
          title: "Saved report views",
          status: "needs-you",
          state: "verifying",
          stage: "merge",
          branch: "feat/sph-5-saved-views",
          pr: 212,
          steps: [
            [135, "Codex gate passed on round 2"],
            [122, "Greptile 5 of 5 on 4c19d0e"],
            [120, "Merge gate: needs an approval from someone else"],
          ],
        }),
        item(HOME, {
          ref: "SPH-11",
          title: "Export reports as CSV",
          status: "building",
          state: "building",
          stage: "build",
          branch: "feat/sph-11-csv-export",
          pr: 214,
          steps: [
            [69, "Plan written, 9 tasks"],
            [52, "Executor done on luna, 14 files changed"],
            [40, "Fresh Claude review, 2 findings fixed"],
            [27, "Live checks, 4 of 4 criteria pass"],
            [25, "Draft PR #214 opened"],
            [19, "Codex gate round 1: 1 P1 finding, fixed"],
            [6, "Codex gate, round 2 of 3"],
          ],
          criteria: [
            "Reports export as CSV",
            "A 10,000-row cap with a note when it is hit",
          ],
          decisions: ["D1 CSV over XLSX", "D2 A 10,000-row cap on CSV exports"],
        }),
        item(HOME, {
          ref: "SPH-13",
          title: "Invoice times in the team's time zone",
          status: "building",
          state: "building",
          stage: "build",
          branch: "fix/sph-13-invoice-timezone",
          steps: [
            [36, "Plan written, 5 tasks"],
            [22, "Executor writing the code"],
          ],
        }),
        item(HOME, {
          ref: "SPH-10",
          title: "Team invites page",
          status: "in-review",
          state: "babysitting",
          stage: "babysit",
          branch: "feat/sph-10-invites",
          pr: 211,
          steps: [
            [59, "Codex gate passed on round 1"],
            [51, "Marked ready for review"],
            [15, "Waiting for Greptile, pass 1 of 2"],
          ],
        }),
        item(HOME, {
          ref: "SPH-15",
          title: "Show plan usage on the account page",
          status: "briefing",
          state: "briefing",
          stage: "brief",
          branch: "",
          steps: [
            [13, "Brief worker started"],
            [8, "Brief worker reading the code"],
          ],
        }),
        item(HOME, {
          ref: "SPH-12",
          title: "Rewrite the invite email",
          status: "queued",
          state: "brief-ready",
          stage: "brief",
          branch: "",
          steps: [[12, "Brief ready, 3 criteria"]],
        }),
        item(HOME, {
          ref: "SPH-14",
          title: "Retry failed billing webhooks",
          status: "queued",
          state: "brief-ready",
          stage: "brief",
          branch: "",
          steps: [[12, "Brief ready, waits for the webhook secret"]],
        }),
        item(HOME, {
          ref: "SPH-8",
          title: "Fix invoice rounding",
          status: "merged",
          state: "done",
          stage: "post",
          branch: "fix/sph-8-rounding",
          pr: 207,
          steps: [
            [11, "Merge gate passed on 0b8e4c3"],
            [10, "Merged under your go of Oct 15"],
          ],
        }),
        item(HOME, {
          ref: "SPH-4",
          title: "Reports page filters",
          status: "merged",
          state: "done",
          stage: "post",
          branch: "feat/sph-4-filters",
          pr: 205,
          steps: [
            [151, "Merge gate passed on 7d2a91c"],
            [150, "Merged under your go of Oct 15"],
          ],
        }),
      ],
      "sphere-api": [],
      "juel-claude": [],
    },
    evidence: { "sphere-app": [], "sphere-api": [], "juel-claude": [] },
    slack: {
      status: {
        connected: true,
        lastCheck: ago(2),
        error: null,
        model: "haiku",
        workspace: null,
      },
      routed: [
        {
          id: riaId,
          project: HOME,
          from: "Ria",
          channel: "#sphere-eng",
          text: "hey, is the CSV export landing today? sales wants to demo it tomorrow",
          permalink: `https://example.slack.com/archives/C0SPHERE/p${ria.replace(".", "")}`,
          thread: [],
          draftPath: draft(riaId),
          loopId: "N-45",
        },
        {
          id: marcoId,
          project: HOME,
          from: "Marco",
          channel: "a DM",
          text: "can you look at the invite email copy before it goes out?",
          permalink: `https://example.slack.com/archives/D0MARCO/p${marco.replace(".", "")}`,
          thread: ["Marco: the new invite email, is that yours?"],
          draftPath: draft(marcoId),
          loopId: "N-47",
        },
        {
          id: leaId,
          project: HOME,
          from: "Lea",
          channel: "#releases",
          text: "which PR fixes the invoice time zone?",
          permalink: `https://example.slack.com/archives/C0RELEASES/p${lea.replace(".", "")}`,
          thread: [
            "You: Invoice rounding fix is out in #207:\n• the PR: https://github.com/example/sphere-app/pull/207\n• the notes: <https://example.com/notes/invoice-rounding|release notes>",
          ],
          draftPath: draft(leaId),
          loopId: "N-48",
        },
      ],
      unrouted: [
        {
          id: `C0GENERAL-${slackTs(18)}`,
          from: "Ana",
          channel: "#general",
          text: "anyone around for a quick call at 3 about the pricing page?",
          permalink: "https://example.slack.com/archives/C0GENERAL/p1",
        },
        {
          id: `C0OPS-${slackTs(40)}`,
          from: "Sam",
          channel: "#ops",
          text: "who owns the staging deploy this week?",
          permalink: "https://example.slack.com/archives/C0OPS/p1",
        },
      ],
    },
    briefings: {
      "sphere-app": [
        {
          summary: {
            id: "b1",
            title: "Pause a member's seat",
            updatedAt: ago(1),
            ref: null,
            deletable: true,
          },
          briefing: {
            busy: false,
            turns: [
              {
                who: "me",
                text: "Admins keep asking to pause someone's seat for a month instead of removing them. I want that.",
              },
              {
                who: "agent",
                text: "Seats live in the billing module, and removing a member goes through removeMember(). Two questions before I draft. Should a paused seat stop billing right away, or at the next period? And can a paused member still sign in, read-only?",
                files: [
                  "apps/api/src/billing/seats.ts",
                  "apps/web/src/routes/members.tsx",
                ],
              },
              { who: "me", text: "Next period. No sign-in while paused." },
              {
                who: "agent",
                text: "Then: a Pause action for admins on the members page, billing stops at the next period, the member can't sign in, and Resume brings everything back. Out of scope: pausing the whole team, and emails to the paused member. The draft is on the right. Anything to change before I create it?",
              },
            ],
            draft: {
              title: "Let admins pause a member's seat",
              description:
                "An admin can pause a member for a while instead of removing them. Billing for the seat stops at the next period, and resuming restores everything.",
              criteria: [
                "Admins can pause and resume a member from the members page",
                "A paused seat stops billing at the start of the next period",
                "A paused member can't sign in until resumed",
                "Resuming restores the member's access and data",
              ],
              outOfScope: [
                "Pausing the whole team.",
                "Emails to the paused member.",
              ],
            },
          },
        },
        {
          summary: {
            id: "b0",
            title: "Export reports as CSV",
            updatedAt: ago(60 * 24),
            ref: "SPH-11",
            deletable: true,
          },
          briefing: {
            busy: false,
            turns: [
              { who: "me", text: "Sales wants reports as a spreadsheet." },
              {
                who: "agent",
                text: "CSV opens everywhere and the reports API pages at 10,000 rows. I drafted CSV with a 10,000-row cap.",
                files: ["apps/api/src/reports/export.ts"],
              },
            ],
            draft: {
              title: "Export reports as CSV",
              description: "Reports export as CSV, capped at 10,000 rows.",
              criteria: [
                "Reports export as CSV",
                "A note shows when the cap is hit",
              ],
              outOfScope: ["XLSX"],
            },
          },
        },
      ],
      "sphere-api": [],
      "juel-claude": [],
    },
    trackers: {
      "sphere-app": {
        tracker: null,
      },
      "sphere-api": {
        tracker: "github",
      },
      "juel-claude": {
        tracker: "github",
      },
    },
    trackerConnected: {
      "sphere-app": {
        synapse: false,
        linear: true,
        jira: false,
        github: true,
        none: true,
      },
      "sphere-api": { github: true, none: true },
      "juel-claude": { github: true, none: true },
    },
    search: [],
  }

  db.evidence["sphere-app"] = [
    evidence(HOME, db, {
      ref: "SPH-8",
      title: "Fix invoice rounding",
      pr: "https://github.com/example/sphere-app/pull/207",
      sha: "0b8e4c3",
      mergedAgo: 10,
      goAgo: 60 * 13,
      record: {
        go: "go",
        gate: "Passed round 1, sol xhigh",
        ci: "14 checks green",
        approval: "A teammate, on 0b8e4c3",
      },
      groups: [
        [
          "Totals round half up to the cent",
          [
            [
              "rounding.test.txt",
              "text",
              "✓ 0.005 rounds to 0.01\n✓ totals match line sums\n18 passed",
            ],
          ],
        ],
        [
          "The PDF and the invoice page show the same total",
          [
            ["invoice-pdf.png", "image"],
            ["invoice-page.png", "image"],
          ],
        ],
      ],
    }),
    evidence(HOME, db, {
      ref: "SPH-4",
      title: "Reports page filters",
      pr: "https://github.com/example/sphere-app/pull/205",
      sha: "7d2a91c",
      mergedAgo: 150,
      goAgo: 60 * 13,
      record: {
        go: "go",
        gate: "Passed round 2, sol xhigh",
        ci: "14 checks green",
        approval: "A teammate, on 7d2a91c",
      },
      groups: [
        [
          "Filters stay in the URL, so a shared link opens the same view",
          [
            ["filters-in-url.png", "image"],
            [
              "reports-filters.spec.txt",
              "text",
              "✓ keeps filters in the URL\n✓ restores a shared link\n6 passed",
            ],
          ],
        ],
        ["Clear all resets the table", [["clear-all.webm", "video"]]],
        [
          "Filters work at phone width",
          [
            ["phone-390.png", "image"],
            ["phone-390-open.png", "image"],
          ],
        ],
      ],
    }),
    evidence(HOME, db, {
      ref: "SPH-3",
      title: "Empty state for reports",
      pr: "https://github.com/example/sphere-app/pull/199",
      sha: "a41f0de",
      mergedAgo: 60 * 24 * 2,
      goAgo: 60 * 24 * 2 + 480,
      record: {
        go: "go",
        gate: "Passed round 1, sol xhigh",
        ci: "13 checks green",
      },
      groups: [
        [
          null,
          [
            ["empty-state.png", "image"],
            ["empty-state-click.webm", "video"],
          ],
        ],
      ],
    }),
  ]

  db.search = [
    {
      group: "Items",
      title: "Export reports as CSV",
      sub: "Building, codex gate round 2 of 3",
      ref: "SPH-11",
      project: HOME,
      route: "progress?item=SPH-11",
    },
    {
      group: "Items",
      title: "Remove the old export modal",
      sub: "Waiting on your answer",
      ref: "SPH-9",
      project: HOME,
      route: "progress?item=SPH-9",
    },
    {
      group: "Needs you",
      title: "Start building SPH-11, SPH-12 and SPH-14",
      sub: "Includes Export reports as CSV",
      ref: "Go",
      project: HOME,
      route: "needs?loop=N-41",
    },
    {
      group: "Decisions",
      title: "CSV over XLSX",
      sub: "SPH-11 D1, decided by the brief worker",
      ref: "D1",
      project: HOME,
      route: "progress?item=SPH-11",
    },
    {
      group: "Decisions",
      title: "A 10,000-row cap on CSV exports",
      sub: "SPH-11 D2, the reports API pages at 10,000",
      ref: "D2",
      project: HOME,
      route: "progress?item=SPH-11",
    },
    {
      group: "Slack",
      title: "Ria: is the CSV export landing today?",
      sub: "#sphere-eng, draft ready",
      ref: "3m",
      project: HOME,
      route: `slack?draft=${encodeURIComponent(draft(riaId).split("/").pop() ?? "")}`,
    },
    {
      group: "Briefings",
      title: "Export reports as CSV",
      sub: "Briefed yesterday, became SPH-11",
      ref: "SPH-11",
      project: HOME,
      route: "briefing?id=b0",
    },
    {
      group: "Evidence",
      title: "export-csv-button.png",
      sub: "SPH-4 Reports page filters",
      ref: "SPH-4",
      project: HOME,
      route: "evidence?item=SPH-4",
    },
    {
      group: "Items",
      title: "Fix invoice rounding",
      sub: "Merged 0b8e4c3",
      ref: "SPH-8",
      project: HOME,
      route: "evidence?item=SPH-8",
    },
    {
      group: "Slack",
      title: "Lea: which PR fixes the invoice time zone?",
      sub: "#releases, draft ready",
      ref: "1h",
      project: HOME,
      route: `slack?draft=${encodeURIComponent(draft(leaId).split("/").pop() ?? "")}`,
    },
    {
      group: "Items",
      title: "STAR dashboard web app, CSV of the queue",
      sub: "juel-claude, building",
      ref: "web",
      project: "juel-claude",
      route: "/juel-claude/progress?item=star-dashboard-web",
    },
  ]
  return db
}
