# Vertical Rulers

Vertical rulers (or "guidelines") are visual markers in a code editor
that help developers maintain appropriate line lengths.
This is especially important for activities like side-by-side code comparisons,
as not all developers have wide displays.

## Recommended Ruler Positions

For this repo, the line width recommendations are:

- **80 characters** is the ideal maximum line width.
  Wrap lines of code by this point as often as possible.
- **100 characters** is OK once in a while,
  if it's more aesthetically pleasing than wrapping.
- **120 characters** _can be_ acceptable
  if the end of the line doesn't change often or is common boilerplate.
- **Over 120 characters** is not acceptable and must be wrapped
  unless there's no other choice.

For text files, wrap lines at commas, periods, or other natural phrasing breaks.
For code files, prefer stacking arguments and chained commands vertically.

Not all file types support wrapping lines in all cases.
When wrapping is not possible (for example, a long URI in a Markdown file),
this guideline may be relaxed.
Where wrapping _is_ supported, keep within the rulers as best as possible.

## How do I apply them?

The positions are already committed to the repo,
so most editors need little or no setup:

- **Visual Studio Code** reads `editor.rulers`
  from [.vscode/settings.json][vsCodeSettingsFile].
- **Visual Studio** reads `guidelines`
  from [.editorconfig][editorConfigFile],
  once the [Editor Guidelines][extension] extension is installed.
- **JetBrains Rider**, and any other editor that supports EditorConfig,
  respects `max_line_length` from the same file.
  Adding `80, 100, 120` to its visual guides setting draws all three.

Any other editor needs the three positions set by hand.
The setting tends to be called something like
"rulers", "visual guides", or "color column";
check your editor's own documentation for the exact name.
Two common ones:

**Sublime Text** — add to your user settings:

```json
{
  "rulers": [80, 100, 120],
}
```

**Vim / Neovim** — add to your [.vimrc][vimRC] or `init.vim`:

```vim
set colorcolumn=80,100,120

" Optional: a subtle gray, instead of the default block of color
highlight ColorColumn ctermbg=236 guibg=#2c2d27
```

Every column shares one highlight group,
so a different color per column is not possible natively.

Happy coding!

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[vsCodeSettingsFile]: ../.vscode/settings.json
[editorConfigFile]: ../.editorconfig

<!-- Public URIs (alphabetical) -->

[extension]: https://marketplace.visualstudio.com/items?itemName=PaulHarrington.EditorGuidelinesPreview
[vimRC]: https://www.freecodecamp.org/news/vimrc-configuration-guide-customize-your-vim-editor
