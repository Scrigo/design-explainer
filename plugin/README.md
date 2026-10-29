# design-explain

Shows the architecture of the current project as an interactive C4 diagram (Context, Container, Component), so a software architect can keep track of what AI coding agents build. Claude analyzes the codebase, writes a [likeC4](https://likec4.dev) model into `.design-explainer/` and opens a local viewer; every relationship carries file:line evidence.

- `/design-explain:show` — analyze the project, (re)generate the model and open the diagram.
- `/design-explain:stop` — stop the viewer. It also stops by itself when the session ends (not on `/clear` or `/resume`).

Install (after adding the `design-explainer` marketplace with `claude plugin marketplace add Scrigo/design-explainer`):

```bash
claude plugin install design-explain@design-explainer
```

Requires Node.js with `npx`. Commit `.design-explainer/` except `run/` to get architecture change reports and history from git.

Full documentation: the README of the [design-explainer](../README.md) repository. License: MIT.
