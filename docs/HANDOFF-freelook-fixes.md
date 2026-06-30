# HANDOFF — Free-look mode: 3 playtest bugs + the attitude-hold spec

**Created 2026-06-29** after the FIRST live playtest of the `flight-camera-redesign-v4` branch (the holistic
redesign — see `docs/RESEARCH.md §v4`, `docs/HANDOFF-flight-tuning.md`, and the
`flight-camera-redesign-handoff` memory). For an agent with **cleared context**. Pair with `CLAUDE.md`
(architecture/contracts). **All three fixes live in one file: `src/client/BirdController.client.luau`.** No
flight-model (`FlightPhysics`/`GameConfig`) changes are needed for any of these.

> The mouse-aim chase camera and the PD instructor tested OK enough to keep iterating; these issues are
> **FREE-LOOK-mode only** (toggle with **Space**). Do NOT regress the mouse-aim no-snap camera or the PD
> instructor while fixing free-look. Validate in Studio (the only real test) after each fix.

---

## The player's spec for free-look (verbatim intent)
> "The AoA and heading should **stay where it is left** in free-look but **also be modifiable by keyboard
> input**, and then **remain** unless QWEASD are pressed or I toggle back to mouse-aim mode. It shouldn't
> gravitate to the last mouse position / revert to the last heading."

So in free-look: **the bird holds its current attitude** (the plant has no auto-level — `STABILITY_RATE=0` —
so *zero* rotational input already means "hold nose/bank and fly where you point" via the grip assist),
**keyboard (W/S/A/D/Q/E) still modifies attitude**, and the new attitude **holds on key release**. Toggling
back to mouse-aim resumes the cursor autopilot.

---

## BUG 1 — bird noses over into a dive when controls are released in free-look  ⬅ highest priority
**Symptom:** in free-look with no keys held, the bird slowly pitches over and ends up diving straight down.

**Root cause (confirmed):** in `onFlightStep`, the `else` branch that runs while free-look is active leaves
`aimApplied.{pitch,roll,yaw}` **FROZEN at its last mouse-aim value** (a deliberate "maintain the maneuver"
design that the player has now explicitly reversed). Those `aimApplied.*` fields are **rate commands** that
get summed into `inputState` every frame:
```lua
inputState.pitch = math.clamp(kbPitch + aimApplied.pitch, -1, 1)   -- ~line 823
```
A non-zero frozen pitch command keeps the engine rotating the nose **every frame** (no auto-level to stop
it), so the nose drifts down and, with gravity, settles into a dive. A frozen rate ≠ a held attitude.

**Fix:** in the free-look branch, **ease `aimApplied` toward 0** instead of freezing it. Then
`inputState = keyboard + ~0`, so zero rotational input holds the attitude and the keyboard sum still lets
QWEASD modify it. Current code (around lines 806–822):
```lua
	-- 1d. Mouse-aim autopilot. While aiming: EASE the applied aim toward the live target and draw the
	-- reticle. While FREE-LOOK is held: FREEZE the aim (hold the last command) so the bird MAINTAINS its
	-- maneuver — e.g. keeps pulling a vertical loop — while you orbit the camera, then resumes on release.
	-- Either way the keyboard AUGMENTS on top (still works in free-look for manual nudges).
	if aimOn and camera then
		local aPitch, aRoll, aYaw = computeMouseAim()
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (aPitch - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (aRoll  - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (aYaw   - aimApplied.yaw)   * resp
		aimGui.Enabled = true
		aimDot.Position    = UDim2.fromOffset(aimCursor.cursorX, aimCursor.cursorY)
		noseMarker.Position = UDim2.fromOffset(aimCursor.noseX, aimCursor.noseY)
	else
		-- Free-look (or mouse-aim off): aimApplied is held FROZEN (not eased to 0) so the maneuver continues.
		aimGui.Enabled = false
	end
```
Replace the **comment block + the `else` branch** with:
```lua
	-- 1d. Mouse-aim autopilot. While aiming: EASE the applied aim toward the live target and draw the
	-- reticle. While FREE-LOOK is active: NEUTRALISE the aim (ease to 0) so the bird HOLDS its current
	-- attitude — the plant has no auto-level (STABILITY_RATE=0), so zero rotational input keeps the nose/
	-- bank exactly where it is (flies where it points via grip). The keyboard SUMS on top below, so QWEASD
	-- still modify the held attitude and it REMAINS on release. Resumes mouse-aim on toggle-back.
	if aimOn and camera then
		local aPitch, aRoll, aYaw = computeMouseAim()
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (aPitch - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (aRoll  - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (aYaw   - aimApplied.yaw)   * resp
		aimGui.Enabled = true
		aimDot.Position    = UDim2.fromOffset(aimCursor.cursorX, aimCursor.cursorY)
		noseMarker.Position = UDim2.fromOffset(aimCursor.noseX, aimCursor.noseY)
	else
		-- FREE-LOOK (or mouse-aim off): ease the aim command to 0 so the bird holds attitude and is
		-- modifiable ONLY by keyboard. It must NOT keep applying the last command (that kept rotating the
		-- nose -> nose-over into a dive).
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (0 - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (0 - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (0 - aimApplied.yaw)   * resp
		aimGui.Enabled = false
	end
```
The `inputState.* = kbX + aimApplied.*` lines just below stay unchanged (keyboard is still additive).

**Watch-item:** if easing-to-0 feels too slow (a brief residual drift on entry), snap instead
(`aimApplied.pitch, aimApplied.roll, aimApplied.yaw = 0, 0, 0`). Ease is gentler; snap is decisive. Playtest.

---

## BUG 2 — chase camera does the ~180° flip again during a loop **in free-look**
**Symptom:** doing a loop while in free-look, the camera snaps ~180° over the top (the old nausea bug, but
only in free-look now — mouse-aim mode is fine).

**Root cause:** `updateCamera` slews the persistent chase direction toward the bird's motion **every frame,
including in free-look** (around line 457):
```lua
cameraState.chaseDir = rotateTowards(prevChase, desiredChase, (CAM.chaseTurnRate or 3.6) * dt)
```
The free-look orbit is then applied **on top of** this still-bird-tracking base, so during a loop the base
direction sweeps through 180° and the view flips. Free-look is supposed to be **world-referenced** (hold the
aspect while the bird maneuvers).

**Fix:** **freeze the chase basis while free-look is active** — only track the bird's motion when NOT
free-looking. Then the orbit rotates a world-fixed offset and the aspect holds through the loop. Current
(lines ~455–458):
```lua
	local desiredChase = -followDir
	local prevChase = cameraState.chaseDir or desiredChase
	cameraState.chaseDir = rotateTowards(prevChase, desiredChase, (CAM.chaseTurnRate or 3.6) * dt)
	local chaseDir = cameraState.chaseDir
```
Replace with:
```lua
	local desiredChase = -followDir
	cameraState.chaseDir = cameraState.chaseDir or desiredChase
	-- FREEZE the chase basis while free-looking so the view is WORLD-referenced (holds its aspect while the
	-- bird loops); only track the bird's motion when NOT free-looking. Without this the base offset kept
	-- following the bird's heading through the loop -> the 180° flip even in free-look.
	if not freeLook.active then
		cameraState.chaseDir = rotateTowards(cameraState.chaseDir, desiredChase, (CAM.chaseTurnRate or 3.6) * dt)
	end
	local chaseDir = cameraState.chaseDir
```
`camUp` is derived from `chaseDir`, so freezing `chaseDir` also stabilises the up reference — no further
change needed. **Optional polish:** in free-look set `lookTarget = position` (drop the `followDir*dist*0.12`
look-ahead lead) so the tiny bird-tracking wobble in the look target is gone too; minor.

---

## BUG 3 — free-look camera PITCH is inverted (vertical only; horizontal pan is correct)
**Symptom:** moving the mouse to look up/down is reversed; left/right panning is fine.

**Root cause / fix:** one sign, line **374** in the `InputChanged` free-look handler:
```lua
		freeLook.pitch = math.clamp(freeLook.pitch - input.Delta.Y * s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT)
```
Flip the `-` to `+`:
```lua
		freeLook.pitch = math.clamp(freeLook.pitch + input.Delta.Y * s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT)
```
Leave the **horizontal** line (`freeLook.yaw = freeLook.yaw - input.Delta.X * s`) untouched — the player says
panning is correct. **If the arrow-key look (lines 385–386, `Up`/`Down`) also feels inverted after this,**
swap their `+ s` / `- s` to match; the player only reported the mouse, so flip those only if testing shows it.

---

## Acceptance criteria (Studio)
1. **Free-look, no keys:** the bird **holds its attitude** — it does NOT nose over or dive. It keeps its
   current heading/AoA indefinitely.
2. **Free-look + keyboard:** W/S/A/D/Q/E modify the attitude; on release the **new** attitude holds (no
   reversion to a prior heading or to the cursor).
3. **Toggle back to mouse-aim:** the cursor autopilot resumes cleanly.
4. **Loop while in free-look:** the camera holds its world aspect — **no 180° flip, no snap**.
5. **Free-look mouse pitch:** up = look up, down = look down (matches horizontal panning's correctness).

## Don't regress
- The **mouse-aim** (non-free-look) camera no-snap behaviour and the PD instructor — those tested OK. Bug 2's
  fix only gates the chase-basis update behind `not freeLook.active`; the mouse-aim path is unchanged.
- The free-look **toggle** (Space) and its survival across crow-swaps / focus-loss.

## Pointers
- All edits: `src/client/BirdController.client.luau` (`onFlightStep` for Bug 1, `updateCamera` for Bug 2, the
  `UserInputService.InputChanged` free-look handler for Bug 3).
- Branch: `flight-camera-redesign-v4` (pushed to origin). `master` is the last HUMAN-VERIFIED build.
- Context: `docs/RESEARCH.md §v4`, `docs/HANDOFF-flight-tuning.md`, memory `flight-camera-redesign-handoff`.
