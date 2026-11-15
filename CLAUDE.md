# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: [CHOOSE: Web / Godot 4 / Unity / Unreal Engine 5]
- **Language**: [CHOOSE: TypeScript / GDScript / C# / C++ / Blueprint]
- **Version Control**: Git with trunk-based development
- **Build System**: [SPECIFY after choosing engine]
- **Asset Pipeline**: [SPECIFY after choosing engine]

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line under this comment is engine-specific,
     and there is none until an engine is set. /setup-engine, the grow's record
     step and /project-settings (engine.name) write
     @docs/engine-reference/<engine>/VERSION.md here for the chosen engine. Skills
     that need the pinned version read that file on demand either way. -->
@docs/engine-reference/godot/VERSION.md


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is not imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
  (exempt: `active.md` appends, agent memory, a subagent's new file at the path
  its orchestrating skill named; see `.claude/rules/agent-memory.md`)
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- Commit after each working step, with a clear message (Emberhollow rule, see
  "How to work" below; it overrides the studio default of no commits without
  user instruction). Pushing still needs user instruction.
- A skipped or dismissed question is not an answer: act on nothing, re-ask in
  plain text and wait
- Started outside this file's folder? Warn first: hooks, deny rules and the
  ask-first mode load only when Claude Code starts here

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** Say "make me a game" (`/prototype`), or run `/start` to begin
> the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)

---

# Emberhollow: project rules for Claude

A cozy-but-dark blacksmith game: Coral Island-style life sim with forging instead of farming, Cult of the Lamb-style art and combat. Read `design/game-brief.md` before any task. It is the design source of truth for this repo.

## Who you work with

Marcel is the designer and owner. He is learning game development and front-end engineering.
- Keep explanations short and plain. Lead with what to do next, and use numbered steps.
- When something is his decision (design, feel, scope), offer two or three options and ask. Don't guess.
- After each feature, say exactly what to play-test and what "good" looks like.

## Tech rules

- **Engine:** Godot 4 (standard build), GDScript only. No C#, no GDExtension, nothing that blocks a web export.
- **Content in data:** recipes, races, items, enemies, zones, dialogue, and balance numbers live in JSON under `data/`. Never hard-code tuning values in scripts.
- **Autoloads:** `GameState` holds day, time, inventory, coin, reputation, relationships, and a `reset()` method. `EventBus` holds cross-scene signals (`item_forged`, `day_ended`, and so on). Scenes talk through these, not by reaching into each other.
- **Input:** everything goes through the Input Map. Keyboard and gamepad trigger the same actions. Actions are per player (`p1_attack`, and so on) so co-op can be added later. No raw key checks.
- **Test hook:** keep a `debug_state_text()` function that returns the current game state as readable text or JSON, so Claude can check state during automated runs.
- **Saves:** go to `user://`, so they work on desktop, web, and Android.
- **Art:** placeholder shapes in the brief's palette until Marcel supplies ArtCraft art. Character art is split into parts for Skeleton2D rigs. Use only original assets, never copies of Cult of the Lamb or any other game's art.

## How to work

1. One feature at a time: plan briefly, build, test, fix, then summarize.
2. After every change, run the project headless (`godot --headless --path . --quit-after <frames>`) or the test scene, and fix every error and warning before reporting done.
3. Commit to Git after each working step, with a clear message.
4. Keep `docs/STATE.md` updated: what exists, what's next, known issues. Any model or person should be able to pick up from it.
5. Prototypes go in `prototypes/<name>/` as standalone scenes and never import from the main game.
6. If the brief is unclear or conflicts with a request, stop and ask Marcel.

## Local tools

Godot executable: C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
