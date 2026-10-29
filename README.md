# design-explainer

A Claude Code plugin that shows the architecture of the project you're working on as an interactive C4 diagram, so a software architect can keep track of what AI coding agents are actually building.

On request, Claude analyzes the current codebase, builds a C4 model (Context, Container, Component), writes it as [likeC4](https://likec4.dev) DSL into the project, and opens it in a local browser viewer. Clicking an element shows its role, technology and connections. Every relationship in the model is backed by evidence: the file and line in the code where the connection lives.

## Requirements

- [Claude Code](https://code.claude.com)
- Node.js with `npx` (likeC4 is run on demand via `npx`; nothing is added to your project's dependencies)
- git (recommended: change reports and history come from git)
- Linux or WSL2 (macOS is untested)

## Installation

This repository is a plugin marketplace. Add it and install the plugin:

```bash
claude plugin marketplace add Scrigo/design-explainer
claude plugin install design-explain@design-explainer
```

For development, add a local clone instead (`claude plugin marketplace add /path/to/design-explainer`). The plugin is then read live from `plugin/`; apply edits with `/reload-plugins`.

## Usage

In any project, inside a Claude Code session:

| Command | What it does |
|---|---|
| `/design-explain:show` | Analyzes the codebase, (re)generates the model, validates it and opens the diagram (starts the viewer if needed, otherwise the open page reloads by itself) |
| `/design-explain:stop` | Stops the viewer for the current project |

You can also just ask, e.g. "show me the architecture of this project". The viewer stops by itself when the Claude Code session ends (but not on `/clear` or `/resume`).

After reviewing the diagram, ask Claude for changes in terms of the diagram — "split `billing`", "why does `orders` call `payments`?", "there are too many connections around `api`". Element IDs map back to code through the model's metadata. Changes are made in the code; the next `/design-explain:show` reflects them.

## What it writes into your project

```
.design-explainer/
├── model/
│   ├── spec.c4      # element kinds (managed by the plugin)
│   ├── model.c4     # elements and relationships
│   └── views.c4     # diagram views
├── config.yaml      # optional hints for the analysis (exclusions, mapping, notes)
├── state.json       # last analyzed commit
├── .gitignore       # ignores run/
└── run/             # viewer pid, port, log (not committed)
```

Commit everything except `run/`: `git diff` of the model then shows how the architecture changed, and `git log` gives its history.

Use `config.yaml` when the folder structure doesn't reflect the intended architecture — e.g. to say a file belongs to another component, or that a directory isn't part of the system.

## Limitations

- The model is extracted by an LLM. Evidence on relationships makes it verifiable, but review it like any other AI output.
- One viewer per project: with two sessions open in the same project, ending one stops the viewer for both (the next `show` starts it again).
- Large repositories are analyzed in a single pass for now.

## Development

- Plugin sources: `plugin/` (skills in `plugin/skills/`, scripts in `plugin/scripts/`, session-end hook in `plugin/hooks/hooks.json`).
- Run without installing: `claude --plugin-dir ./plugin`. A plugin installed from a local marketplace path is read live; apply edits with `/reload-plugins`.
- Validate: `claude plugin validate ./plugin` and `claude plugin validate .`
- The likeC4 version is pinned in `plugin/scripts/common.sh`.
- Design and rationale: [docs/architecture.md](docs/architecture.md).

## License

[MIT](LICENSE)
