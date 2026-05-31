# Git Sub-Agent for KiloCode / Nemotron Super

## Overview

The Git Sub-Agent specializes in Git operations within the KiloCode agentic workflow. It acts as a reliable handler for version control tasks, integrating seamlessly with the orchestrator (main Nemotron Super agent).

## Responsibilities

- **Evaluate Diffs**: Analyze `git diff` outputs, provide summaries, suggest improvements or identify issues in changes.
- **Commit Changes**: Stage appropriate files, generate conventional or descriptive commit messages, execute commits.
- **Push Changes**: Push commits to the remote repository (e.g., GitHub), handle branch creation/pushing if necessary.
- **Other Git Ops**: Pull latest changes, manage branches, resolve simple conflicts when instructed.

## Interaction with Orchestrator

- Receives specific git tasks from the orchestrator agent.
- Executes operations using available tools/shell/git commands.
- Reports back status, output, diffs, or errors to the orchestrator.
- Can be called in a loop for iterative development workflows.

## Example Usage in Workflow

Orchestrator: "Review the current diff and commit with message 'feat: add new feature' then push."
Git Agent: Evaluates diff -> Commits -> Pushes -> Confirms success.

This agent ensures all code changes are properly versioned and synchronized.