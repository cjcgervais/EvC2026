<#
  SessionStart hook for Eagles vs Crows.
  Prints a compact orientation banner to stdout - Claude Code injects it into the
  new session's context so a cleared-context agent lands oriented and knows to run
  the governing harness. Deliberately terse + mostly invariant (the living roadmap
  lives in docs/HANDOFF.md, which this points AT rather than duplicating, so it
  never goes stale). Always exits 0 - a hook failure must never block a session.

  ASCII-only on purpose: Windows PowerShell 5.1 reads this .ps1 as ANSI and would
  mangle any emoji/em-dash into mojibake in the injected context. Keep it ASCII.
#>
$ErrorActionPreference = 'SilentlyContinue'

# A little live context (cheap, informative). Falls back silently if git is absent.
$branch = (git rev-parse --abbrev-ref HEAD) 2>$null
$head   = (git log -1 --pretty=format:'%h %s') 2>$null

Write-Output @"
[ EAGLES vs CROWS ] session start. This project is GOVERNED by the evc-loop harness.

>> Run  /evc-loop  to work under the governing loop (SOP-tuned iterate -> verify ->
   red-team -> memory -> handoff -> approved commit). It enforces the rules below.

ORIENT FIRST (read in order):
  1. docs/HANDOFF.md - the COLD START box + newest SESSION block = current state + roadmap.
  2. The LOCKED CONTROL SPECS registry (CS-1..CS-9) in docs/HANDOFF.md.
  3. CLAUDE.md (architecture + contracts) | project MEMORY.md (index).

INVARIANT GUARDRAILS (do not violate - full text in the skill):
  - Eagle flight/control/camera feel is SIGNED OFF. Frontier = crow AI + 1-v-4 + combat.
  - LOCKED specs are protected - grep the CS registry before ANY control/kernel edit;
    never change a locked behavior collaterally. ASK, don't guess on control feel.
  - ONE change at a time; checkpoint before kernel edits; keep the build green.
  - Ground truth is Chad's Studio Play - build.ps1 does NOT run or syntax-check Luau.
  - flight == balance: reason about the whole 1-eagle-vs-4-crow fight on every number.
  - git commit/push are gated to ASK for Chad's approval.

Branch: $branch    HEAD: $head
"@

exit 0
