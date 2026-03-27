# AI Development Guidelines for Claude Code

## Project Overview

This project is a Roblox game inspired by Raft. The game includes ocean survival mechanics, player-owned islands, resource collection, crafting, UI systems, and multiplayer synchronization.

The codebase is large and consists of many interconnected files. You must treat this project as a multi-file production system, not a single-script prototype.

---

## General Rules

* Do NOT write comments in the code.
* Write code like an experienced Roblox developer.
* Keep code clean, minimal, and production-ready.
* Do not explain the code unless explicitly asked.
* Do not include debug prints unless requested.
* Avoid unnecessary abstractions.

---

## Code Style

* Use clear and simple naming (no overly complex names).
* Follow typical Roblox Lua conventions.
* Prefer short and readable functions.
* Avoid deeply nested logic.
* Do not over-engineer systems.

---

## File Structure Awareness

* Always assume there are many existing scripts.
* Do NOT rewrite entire systems unless asked.
* Only modify or extend what is necessary.
* Respect existing architecture and naming.

---

## Modularity

* Write reusable modules when appropriate.
* Do not duplicate logic across files.
* Keep responsibilities separated (UI, logic, data, etc).

---

## Multiplayer & Data

* Always consider multiplayer behavior.
* Do not write client-only logic for server systems.
* Be careful with RemoteEvents and RemoteFunctions.
* Assume player data must be saved and loaded properly.

---

## Performance

* Avoid heavy loops or expensive operations.
* Be mindful of memory and replication cost.
* Optimize only when necessary, but avoid bad practices.

---

## UI

* UI must be clean and responsive.
* Assume UI updates dynamically.
* Do not hardcode values if they can change.

---

## Communication Rules

* If something is unclear, ask for clarification before coding.
* Do not make assumptions about missing systems.
* If a feature depends on something not implemented, say it.

---

## Output Rules

* Always provide full working code.
* Do not send partial snippets unless requested.
* Clearly specify where the code should be placed.

---

## Important

You are working with a real project, not a tutorial.

Act like a professional developer contributing to an existing codebase.
