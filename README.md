# c3ed

text editor and micro-IDE for C3

```bash
c3c build linux
# c3c build windows
# c3c build macos

# Open specific file or project folder
build/c3ed src/myfile.c3
```

---

## Shortcuts

### Navigation & Cursors
|  |  |
| :--- | :--- |
| `Arrows`, `Home`, `End` | Move cursor |
| `Ctrl + Left` / `Right` | Word jump |
| `PageUp` / `PageDown` | Page jump |
| `Ctrl + Home` / `End` | Top / bottom of file |
| `Shift + Navigation` | Extend selection |
| `Ctrl + Shift + Home` / `End` | Select to top / bottom |
| `Ctrl + A` | Select all |
| `Ctrl + Shift + Up` / `Down` | Multi-cursor column |
| `Ctrl + D` | Select next occurrence |
| `Ctrl + B` or `Ctrl + Shift + \` | Jump matching bracket `()`, `[]`, `{}` |
| `Ctrl + G` | Go to line |

### Editing
|  |  |
| :--- | :--- |
| `Tab` / `Shift + Tab` | Indent / outdent |
| `Ctrl + /` or `Ctrl + M` | Toggle comment `//` |
| `Ctrl + Shift + D` | Duplicate line |
| `Ctrl + Shift + K` | Delete line |
| `Alt + Up` / `Down` | Move line up / down |
| `Ctrl + Backspace` / `Del` | Delete word left / right |
| `Ctrl + Shift + U` / `Ctrl + U` | Uppercase / lowercase |
| `Ctrl + Z` / `Ctrl + Y` | Undo / redo |
| `Ctrl + C` / `Ctrl + X` / `Ctrl + V` | Copy / cut / paste |

### Search & Workspace
|  |  |
| :--- | :--- |
| `Ctrl + O` / `Ctrl + P` | Quick file open & path navigator |
| `Ctrl + Shift + F` | Fuzzy project search |
| `Ctrl + F` | Find in file |
| `Ctrl + H` | Find & replace |
| `F3` / `Shift + F3` | Next / previous match |
| `Alt + C` | Toggle case sensitivity |
| `Ctrl + R` | Jump next symbol |
| `Ctrl + Shift + R` | Document symbol outline |

### Tabs & File
|  |  |
| :--- | :--- |
| `Ctrl + T` | New tab |
| `Ctrl + W` | Close tab |
| `Ctrl + Tab` / `Ctrl + Shift + Tab` | Next / previous tab |
| `Alt + 1` .. `Alt + 9` | Switch to tab N |
| `Ctrl + S` / `Ctrl + Shift + S` | Save / save as |
| `Ctrl + Q` | Quit |

### Tools & Build
|  |  |
| :--- | :--- |
| `Ctrl + Shift + B` | `c3c build` |
| `F5` | `c3c run` |
| `Ctrl + F5` | `c3c compile-run <file>` |
| `Ctrl + Shift + F5` | `c3c compile <file>` |
| `F1` | Go to definition |
| `Ctrl + Space` | Trigger autocomplete |
| `Ctrl + ~` | Toggle build terminal panel |
| `Ctrl + +` / `Ctrl + -` / `Ctrl + Wheel` | Font zoom |

---

_go to def should be F12 but I must recompile raylib to prevent F12 take a screenshot and I'm lazy._

---

### File Overview

```text
src/
- config.c3         // Theme, colors, editor settings
- gfx.c3            // Platform/Graphics abstraction layer (wraps Raylib)
- piecetable.c3     // Piece table data structure, undo stack, fast search
- syntax.c3         // Tokenizer, lexer, line state machine
- document.c3       // Document model, cursors, Tab viewport, text actions
- workspace.c3      // Workspace, DiagnosticsStore, GitDiffStore, FileWatcher, LSP symbols
- modal.c3          // ModalState, Find/Replace, Fuzzy file picker, Grep, Symbol outline
- ui_font.c3        // Font loading, fallback font chain, glyph drawing
- ui_render.c3      // Layout metrics, UI widgets, read-only render pipeline
- editor.c3         // Editor coordinator, commands, keybindings, session persistence
- main.c3           // App entry point, window lifecycle, event polling loop
```