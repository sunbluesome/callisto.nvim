# callisto.nvim

Edit Jupyter notebooks in Neovim with full LSP support -- no scattered files, no missed changes.

<!-- TODO: demo screencast -->
<!-- ![demo](https://...) -->

## Why callisto?

### The Problem

Data scientists who use Neovim face a fundamental friction with Jupyter notebooks:

- **No editor intelligence.** `.ipynb` files are JSON. LSP, treesitter, completion -- none of it works. You lose everything that makes Neovim productive.
- **Scattered `.py` files.** Tools like jupytext solve the editing problem by creating paired `.py` files, but those files clutter your project tree and need to be gitignored or managed separately.
- **Invisible external changes.** When Jupyter, Claude Code, or any other tool modifies a notebook, your Neovim buffer has no idea. You are editing a stale version and will silently overwrite the external changes on save.
- **No execution from the editor.** To run a notebook or export results, you have to leave Neovim entirely.

### The Solution

callisto.nvim converts `.ipynb` to Python in a **temporary directory** -- your project stays clean. A **file watcher** monitors the original `.ipynb` so that external edits (from Jupyter, AI agents, collaborators) are reflected in your buffer instantly. Output cells are always preserved. You can execute notebooks and export Markdown without leaving the editor.

```
:edit experiment.ipynb     -- opens as Python with full LSP
(edit as normal)
:write                     -- saves back to .ipynb (outputs preserved)
```

If something else modifies `experiment.ipynb` while you are editing, callisto detects it and updates your buffer automatically. If you have unsaved changes, you get a warning instead of silent data loss.

## Design Principles

### Clean project tree

By default, converted `.py` files live in a temporary directory and are cleaned up automatically. Your project tree never sees them. If you prefer keeping `.py` alongside `.ipynb` (e.g. for version control), the `sync` option enables that.

### Real-time external change detection

callisto uses libuv's `fs_event` to watch the original `.ipynb` file. When an external tool -- Jupyter, an AI agent, a collaborator's script -- modifies the notebook, your buffer updates immediately without polling or manual reload. If you have unsaved changes, you get a warning instead of silent data loss.

### Notebook execution without leaving the editor

`:NotebookRun` executes the notebook in-place and reloads the results. `:NotebookExport` exports to Markdown. Both work from within the buffer.

### Output cell preservation

Every save uses jupytext's `--update` flag, so execution results, plots, and other outputs in the `.ipynb` are never lost -- even though you are editing only the code cells.

## Features

- Opens `.ipynb` files as Python with full LSP, treesitter, and completion support
- Saves back to `.ipynb` transparently on `:w` (output cells are preserved)
- Watches for external changes (e.g. from Jupyter, Claude Code) and auto-reloads the buffer
- Execute notebooks in-place via `nbconvert`
- Export notebooks to Markdown
- Optional `sync` mode to keep `.py` alongside `.ipynb` (like native jupytext pairing)
- Buffer-local keymaps for notebook operations
- User autocmd events for custom workflows

## Quick Start

### Requirements

- Neovim >= 0.10
- [jupytext](https://github.com/mwouts/jupytext) (`pip install jupytext`)
- [jupyter nbconvert](https://nbconvert.readthedocs.io/) (`pip install nbconvert`) -- for `:NotebookRun` and `:NotebookExport`

### Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "sunbluesome/callisto.nvim", opts = {} }
```

### Usage

Open any `.ipynb` file and edit it as Python. Save with `:w`. That's it.

```vim
:edit notebook.ipynb       " opens as Python with LSP
:NotebookRun               " execute and reload results
:NotebookExport            " export to Markdown
```

## Configuration

Default values are shown below. You only need to specify values you want to change.

```lua
{
  "sunbluesome/callisto.nvim",
  opts = {
    tmpdir = nil,                    -- base directory for temp files (nil = OS default)
    sync = false,                    -- save .py alongside .ipynb (like native jupytext)
    venv = ".venv",                  -- venv directory name (nil to disable)
    run = {
      auto_export = true,          -- auto-export markdown after :NotebookRun
    },
    watcher = {
      debounce_ms = 200,           -- debounce delay for external change detection (ms)
      restart_delay_ms = 300,      -- delay before restarting watcher after write (ms)
    },
    keys = {
      run = "<leader>nr",          -- keymap for :NotebookRun (nil to disable)
      export = "<leader>ne",       -- keymap for :NotebookExport (nil to disable)
    },
  },
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tmpdir` | `string?` | `nil` | Base directory for temp files. `nil` uses OS default. Ignored when `sync = true` |
| `sync` | `boolean` | `false` | Save `.py` files alongside `.ipynb` instead of in tmpdir. Opening a `.py` with a paired `.ipynb` auto-syncs |
| `venv` | `string?` | `".venv"` | Venv directory name to find `jupytext`/`jupyter`. Searched in cwd. `nil` to disable |
| `run.auto_export` | `boolean` | `true` | Automatically export to Markdown after `:NotebookRun` |
| `watcher.debounce_ms` | `integer` | `200` | Debounce delay for external change detection |
| `watcher.restart_delay_ms` | `integer` | `300` | Delay before restarting watcher after write |
| `keys.run` | `string?` | `"<leader>nr"` | Buffer-local keymap for `:NotebookRun`. `nil` to disable |
| `keys.export` | `string?` | `"<leader>ne"` | Buffer-local keymap for `:NotebookExport`. `nil` to disable |

## Commands

| Command | Description |
|---------|-------------|
| `:NotebookRun` | Execute the notebook in-place via `nbconvert`. Auto-exports to Markdown if `run.auto_export` is enabled. |
| `:NotebookExport` | Export the notebook as Markdown to the same directory as the `.ipynb` file. |

## Keymaps

The following buffer-local keymaps are registered in notebook buffers by default:

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>nr` | `:NotebookRun` | Execute notebook |
| `<leader>ne` | `:NotebookExport` | Export notebook to Markdown |

These keymaps are only active in buffers opened via callisto (i.e. `.ipynb` files). They do not affect normal Python files. Keymaps can be customized or disabled via `opts.keys`.

## Events

callisto.nvim emits `User` autocmd events that you can hook into for custom workflows:

| Event | Description |
|-------|-------------|
| `CallistoNotebookWritten` | Fired after buffer changes are saved back to `.ipynb` |
| `CallistoNotebookReloaded` | Fired after an external change is detected and the buffer is reloaded |

Example:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CallistoNotebookWritten",
  callback = function(args)
    print("Notebook saved: buffer " .. args.data.bufnr)
  end,
})
```

## Health Check

Run `:checkhealth callisto` to verify dependencies and view current configuration.

## Architecture

See [docs/architecture.md](docs/architecture.md) for internal design details, module structure, and sequence diagrams.

## License

[MIT](LICENSE)
