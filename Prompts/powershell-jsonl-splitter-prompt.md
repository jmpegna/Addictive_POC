# PowerShell Expert -- JSONL Splitter with URL Routing & UTF-8 Safety

You are an expert PowerShell engineer.

Design and implement a **simple, reliable, production-ready PowerShell
script** that processes a JSONL file and writes one JSON file per line.

------------------------------------------------------------------------

## Functional Requirements

### 1. Input / Output

-   Input: UTF-8 encoded `.jsonl` file (one JSON object per line).
-   Output: one `.json` file per input line.
-   Output JSON must be UTF-8 encoded **without BOM**.

------------------------------------------------------------------------

### 2. URL-Based Routing

Each JSON object contains:

``` json
{ "url": "https://gafasaddictive.com/..." }
```

Route files into subfolders under the output directory:

  -----------------------------------------------------------------------
  Folder                       Match Rule
  ---------------------------- ------------------------------------------
  `addictive`                  `gafasaddictive.com/addictive-`

  `colaboradores`              `gafasaddictive.com/colaboradores/`

  `comprar`                    `gafasaddictive.com/comprar_` OR
                               `gafasaddictive.com/comprar/`

  `gafas`                      `gafasaddictive.com/gafas-`

  `producto`                   `gafasaddictive.com/producto/addictive-`
                               OR `gafasaddictive.com/producto/`

  `tienda`                     `gafasaddictive.com/tienda/`

  `others`                     anything else
  -----------------------------------------------------------------------

First matching rule wins.

------------------------------------------------------------------------

### 3. Filename Logic

-   Filename = remaining part of the URL after the matched prefix.
-   If empty → use friendly name of the unmatched URL, using underscores. For example, "https://gafasaddictive.com/cordon-silicona-gafas" would produce name = "gafasaddictive.com_cordon-silicona-gafas.json".
-   Remove query strings and fragments.
-   Sanitize for Windows filenames.
-   Prevent collisions by appending `-2`, `-3`, etc.

------------------------------------------------------------------------

### 4. Encoding Safety

-   Read input as UTF-8.
-   Repair common UTF-8 mojibake in **all string fields** (e.g., UTF-8
    decoded as Latin-1 / CP1252).
-   Script itself must be ASCII-safe (no mojibake literals embedded).

------------------------------------------------------------------------

### 5. Filesystem Reliability

-   Resolve absolute paths.
-   Always create destination folders **before writing files**.
-   Never assume folders already exist.

------------------------------------------------------------------------

### 6. Observability

-   `-Verbose` prints one line per processed file with its final output
    path.
-   At the end print:
    -   total lines
    -   files written
    -   failures
-   Failures must not stop the script.

------------------------------------------------------------------------

### 7. Simplicity Constraints

-   Avoid over-engineering.
-   No fragile `.Count` usage on unknown objects.
-   No dependency on script file encoding.
-   Prefer clear imperative code over complex abstractions.

------------------------------------------------------------------------

### 8. Compatibility

Must work on:

-   Windows PowerShell 5.1
-   PowerShell 7+

No external modules.

------------------------------------------------------------------------

## Execution

The script must run as:

``` powershell
.\Split-JsonlByUrl.ps1 -InputPath .\file.jsonl -OutputDir .\out -Verbose
```

------------------------------------------------------------------------

## Quality Bar

The script must:

-   Successfully generate files for hundreds of lines.
-   Never fail due to path issues.
-   Never fail due to encoding issues.
-   Never silently skip writes.
-   Be understandable by a senior engineer in one read.

------------------------------------------------------------------------
