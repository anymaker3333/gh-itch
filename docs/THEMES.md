# Menu themes

Game Hub keeps its menu palette in `Palette` and renders the shared controls from
`ThemeBuilder`. A theme is a small JSON file that overrides colour tokens; it
contains no code and cannot load resources.

## Selecting and importing

Open **Settings → Appearance**.

- Built-in themes are always available: **Game Hub (default)** and **Casino**.
- **Upload theme…** reads a `.json` file, validates it, copies it into the user
  data directory and applies it immediately.
- **Export example theme…** writes a complete starter file with every token at
  its current default value.
- A custom theme can be removed again from the same page. Built-in themes
  cannot be deleted.

Imported files live in `user://themes/`. On Linux this is normally:

```
~/.local/share/godot/app_userdata/Game Hub/themes/
```

The exact path is shown in the Appearance section at runtime.

## File format

```json
{
  "format": "gamehub-theme/1",
  "name": "My Theme",
  "colors": {
    "bg_base": "#101820",
    "bg_panel": "#18242e",
    "text": "#f2f6fa",
    "accent": "#ffb347",
    "accent_hover": "#ffc76d"
  }
}
```

The `format`, `name` and `colors` fields are required. `name` is shown in the
theme picker and is limited to 48 characters. Unknown fields are ignored.

### Required colours

| Token | Used for |
| --- | --- |
| `bg_base` | Main application background |
| `bg_panel` | Panels and cards |
| `text` | Primary text |
| `accent` | Primary actions, selection and focus accents |

### Optional colours

| Token | Used for |
| --- | --- |
| `bg_deepest` | Sidebar and recessed surfaces |
| `bg_elevated` | Inputs, raised cards, hovered rows |
| `bg_hover` | Hovered surfaces |
| `bg_active` | Pressed/active surfaces |
| `border` | Standard 1 px borders |
| `border_strong` | Emphasised borders |
| `text_muted` | Secondary text and captions |
| `text_dim` | Disabled and tertiary text |
| `text_on_accent` | Text on filled accent buttons |
| `accent_hover` | Hovered primary actions |
| `accent_pressed` | Pressed primary actions |
| `accent_soft` | Accent-tinted panels |
| `accent_dim` | Accent-tinted recessed surfaces |
| `positive` | Success states |
| `warning` | Warning states |
| `danger` | Destructive actions and errors |
| `info` | Informational states |
| `focus` | Keyboard focus outline |

Colours accept Godot's HTML colour syntax (`#rgb`, `#rrggbb`, `#rrggbbaa`).
Missing optional tokens are inherited from the
Game Hub default palette. Invalid hex values or a missing required token cause
the import to be rejected; the active theme is never changed in that case.

## Built-in Casino example

[`data/themes/casino.json`](../data/themes/casino.json) is both the built-in
Casino theme and a complete format example. It uses a green felt background,
warm card-room text and a brass accent. Copy it, rename it, and import it to
start a custom theme.
