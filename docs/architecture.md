# Architecture

## Module Overview

```
lua/callisto/
  init.lua        Setup, config defaults, buffer state management, autocmd registration
  converter.lua   jupytext I/O: read (.ipynb -> .py), write (.py -> .ipynb), cleanup
  watcher.lua     File system watcher (libuv fs_event) with debounce
  commands.lua    User commands: NotebookRun, NotebookExport
  util.lua        Shared helpers: notify, get_buf_state, run_sync, run_async
  health.lua      :checkhealth callisto

ftdetect/
  ipynb.lua       Register ipynb filetype
```

## Data Flow

### Opening a notebook

When you open a `.ipynb` file, callisto intercepts the read via `BufReadCmd` and converts it to a Python script using jupytext. The buffer is renamed to `.py` so LSP servers (Pyright, ruff, etc.) attach correctly.

```mermaid
sequenceDiagram
    participant U as User
    participant N as Neovim
    participant C as callisto
    participant J as jupytext

    U->>N: :edit test.ipynb
    N->>C: BufReadCmd event
    C->>J: jupytext --to py:percent --output /tmp/.../test.py test.ipynb
    J-->>C: test.py (converted)
    C->>N: Load content into buffer
    C->>N: Rename buffer to test.py
    C->>N: Set filetype = python
    Note over N: LSP, treesitter, completion activate
    C->>C: Start file watcher on test.ipynb
```

### Saving changes

On `:w`, callisto writes the buffer content to the `.py` file, then uses jupytext to convert it back to `.ipynb`. The `--update` flag preserves existing output cells (execution results, plots, etc.).

```mermaid
sequenceDiagram
    participant U as User
    participant N as Neovim
    participant C as callisto
    participant J as jupytext

    U->>N: :write
    N->>C: BufWriteCmd event
    C->>C: Stop file watcher
    C->>J: jupytext --to notebook --update --output test.ipynb test.py
    J-->>C: test.ipynb (updated)
    C->>N: Set modified = false
    C-->>N: Emit CallistoNotebookWritten event
    C->>C: Restart file watcher (after delay)
```

### External change detection

When an external tool (e.g. `jupyter`, Claude Code) modifies the `.ipynb` file, the file watcher detects the change, re-converts via jupytext, and updates the buffer.

```mermaid
sequenceDiagram
    participant E as External tool
    participant W as File watcher
    participant C as callisto
    participant J as jupytext
    participant N as Neovim

    E->>E: Modify test.ipynb
    W->>W: fs_event detected
    W->>W: Debounce (200ms)
    alt Buffer has unsaved changes
        W->>N: Warning notification
    else Buffer is clean
        W->>J: jupytext --to py:percent --output test.py test.ipynb
        J-->>W: test.py (re-converted)
        W->>N: Update buffer content
        W-->>N: Emit CallistoNotebookReloaded event
    end
```

### Notebook execution

`:NotebookRun` executes the notebook in-place using `jupyter nbconvert`. If `run.auto_export` is enabled, it automatically exports the results to Markdown.

```mermaid
sequenceDiagram
    participant U as User
    participant C as callisto
    participant NB as nbconvert
    participant N as Neovim

    U->>C: :NotebookRun
    C->>C: Save if modified
    C->>C: Stop file watcher
    C->>NB: jupyter nbconvert --execute --inplace test.ipynb
    NB-->>C: Execution complete
    C->>N: Reload buffer from updated .ipynb
    opt auto_export = true
        C->>NB: jupyter nbconvert --to markdown test.ipynb
        NB-->>C: test.md exported
    end
    C->>C: Restart file watcher
```

## Module Interactions

Modules are decoupled via User autocmd events instead of direct function calls:

- `converter.lua` emits `CallistoNotebookWritten` after a successful write
- `watcher.lua` emits `CallistoNotebookReloaded` after reloading from an external change

This allows users to hook into these events for custom workflows without modifying the plugin.

## Buffer State

Each managed buffer has a `callisto.BufState` entry in `_buffers`:

| Field | Type | Description |
|-------|------|-------------|
| `ipynb_path` | `string` | Absolute path to the `.ipynb` file |
| `tmp_py` | `string` | Path to the `.py` file (tmpdir or alongside `.ipynb` in sync mode) |
| `tmpdir` | `string?` | Path to temporary directory. `nil` in sync mode (no cleanup) |
| `watcher` | `userdata?` | libuv `fs_event` handle |
