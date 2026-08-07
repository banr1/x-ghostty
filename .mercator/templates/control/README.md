# Control-plane bind templates

These `*.tmpl` files are the canonical sources that `mercator-init.sh`
(`just init <path>`) renders into the live control-plane files when binding this
`.mercator` control plane to a single target project:

| Template | Rendered to |
| --- | --- |
| `settings.json.tmpl` | `.claude/settings.json` |
| `CLAUDE.md.tmpl` | `CLAUDE.md` |
| `justfile.tmpl` | `justfile` |

## Placeholder tokens

Rendering is a literal substitution of these tokens (chosen to never collide
with real prose or paths):

| Token | Replaced with | Example |
| --- | --- | --- |
| `__MERCATOR_PROJECT_PATH__` | PROJECT_ROOT relative to CONTROL_ROOT | `../my-project` |
| `__MERCATOR_PROJECT_TITLE__` | PROJECT_ROOT basename | `my-project` |
| `__MERCATOR_PROJECT_ABS__` | PROJECT_ROOT resolved absolute (physical) path | `/home/u/workspace/my-project` |
| `__MERCATOR_CONTROL_ABS__` | CONTROL_ROOT resolved absolute (physical) path | `/home/u/workspace/.mercator` |

The two `_ABS_` tokens exist because Claude Code matches permission path rules
and sandbox filesystem paths against resolved absolute targets; a relative
spelling resolves against a base the framework does not control and fails
silently (META.md §28.5).

Editing bindings by hand is discouraged: change the templates (or re-run
`just init <path>`) so a re-bind stays reproducible. The live `.claude/settings.json`,
`CLAUDE.md`, and `justfile` shipped in the distribution are the *unbound, safe*
versions — running `init` overwrites them with the bound versions.
