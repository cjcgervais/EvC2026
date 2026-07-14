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
[ EAGLES TO THE RESCUE ] session start. This project is GOVERNED by the evc-loop harness.

>> STANDING ORDER (Chad, S32): the game is EAGLES TO THE RESCUE (combat SHELVED). The Phase-0
   slice is BUILT. Immediately run  /evc-loop  and work the RESCUE Phase-0 QUEUE in the
   docs/HANDOFF.md COLD START box AS A LOOP - one item at a time (propose -> red-team ->
   build -> verify green -> log), looping until the queue is exhausted or Chad returns to
   playtest. Do NOT wait for further instruction; do NOT drift back to combat. FUN is the
   only thing that needs Chad's Play - build/tune everything else autonomously in the loop.

ORIENT FIRST (read in order):
  1. docs/HANDOFF.md - the COLD START box (rescue queue + standing loop order) = current state.
  2. The LOCKED CONTROL SPECS registry (CS-1..CS-9) in docs/HANDOFF.md.
  3. CLAUDE.md (architecture + contracts) | project MEMORY.md (index) | docs/EAGLES-TO-THE-RESCUE-plan.md.

INVARIANT GUARDRAILS (do not violate - full text in the skill):
  - Eagle flight/control/camera feel + the flight KERNEL are SIGNED OFF + LOCKED. Rescue is built
    AROUND them (triggers + presentation + world + meta) - NEVER in the kernel/camera/aim law.
  - LOCKED specs are protected - grep the CS registry before ANY control/kernel edit;
    never change a locked behavior collaterally. ASK, don't guess on control feel.
  - ONE change at a time; checkpoint before kernel edits; keep the build green.
  - Ground truth is Chad's Studio Play - build.ps1 does NOT run or syntax-check Luau (verify.ps1 does static analysis).
  - Every rescue step: kid-FLOOR (a 5-yo succeeds) AND skill-CEILING (a 15-yo shines) in the SAME mechanic. Non-lethal always (P3).
  - git commit/push are gated to ASK for Chad's approval.

Branch: $branch    HEAD: $head
"@

exit 0
