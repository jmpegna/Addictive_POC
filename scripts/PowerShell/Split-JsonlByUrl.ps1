<#
Split-JsonlByUrl.ps1

Splits a UTF-8 JSONL file (one JSON object per line) into individual JSON files,
routing them into subfolders based on URL patterns.

Example execution:

.\Split-JsonlByUrl.ps1 `
  -InputPath $PWD\..\..\website\addictive.jsonl `
  -OutputDir $PWD\..\..\website\categorized_content `
  -Verbose

Works on:
- Windows PowerShell 5.1
- PowerShell 7+

No external modules required.
#>

[CmdletBinding()]
param(
    # Path to the input JSONL file
    [Parameter(Mandatory)]
    [string]$InputPath,

    # Output directory where categorized files will be written
    [Parameter(Mandatory)]
    [string]$OutputDir
)

# ============================================================
# Helper functions
# ============================================================

# Resolve a path to an absolute filesystem path
function Resolve-FullPath {
    param([string]$Path)
    [System.IO.Path]::GetFullPath($Path)
}

# Create a directory if it does not already exist
function Ensure-Directory {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
}

# Attempt to repair common UTF-8 mojibake caused by Latin-1 / CP1252 decoding
function Repair-Mojibake {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    try {
        $bytes = [System.Text.Encoding]::GetEncoding(28591).GetBytes($Text)
        [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        $Text
    }
}

# Recursively walk an object and repair all string fields
function Repair-ObjectStrings {
    param($Obj)

    if ($null -eq $Obj) { return $null }

    if ($Obj -is [string]) {
        return (Repair-Mojibake $Obj)
    }

    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($k in @($Obj.Keys)) {
            $Obj[$k] = Repair-ObjectStrings $Obj[$k]
        }
        return $Obj
    }

    if ($Obj -is [System.Collections.IEnumerable] -and -not ($Obj -is [string])) {
        $i = 0
        foreach ($v in $Obj) {
            $Obj[$i] = Repair-ObjectStrings $v
            $i++
        }
        return $Obj
    }

    return $Obj
}

# Remove invalid characters from filenames
function Sanitize-Filename {
    param([string]$Name)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) {
        $Name = $Name.Replace($c, '_')
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "index"
    }

    return $Name
}

# Determine routing folder and matched prefix from URL
function Get-Route {
    param([string]$Url)

    # First matching rule wins
    $rules = @(
        @{ Folder="addictive";     Prefix="https://gafasaddictive.com/addictive-" },
        @{ Folder="colaboradores"; Prefix="https://gafasaddictive.com/colaboradores/" },
        @{ Folder="comprar";       Prefix="https://gafasaddictive.com/comprar_" },
        @{ Folder="comprar";       Prefix="https://gafasaddictive.com/comprar/" },
        @{ Folder="gafas";         Prefix="https://gafasaddictive.com/gafas-" },
        @{ Folder="producto";      Prefix="https://gafasaddictive.com/producto/addictive-" },
        @{ Folder="producto";      Prefix="https://gafasaddictive.com/producto/" },
        @{ Folder="tienda";        Prefix="https://gafasaddictive.com/tienda/" }
    )

    foreach ($r in $rules) {
        if ($Url.StartsWith($r.Prefix)) {
            return $r
        }
    }

    return @{ Folder="others"; Prefix="" }
}

# Remove ?query and #fragment from URL
function Remove-QueryAndFragment {
    param([string]$Url)

    $q = $Url.IndexOfAny(@('?', '#'))
    if ($q -ge 0) {
        return $Url.Substring(0, $q)
    }
    return $Url
}

# Generate a non-colliding output file path
function Get-UniqueFilePath {
    param(
        [string]$Dir,
        [string]$BaseName
    )

    $name = $BaseName
    $i = 1

    while (Test-Path -LiteralPath (Join-Path $Dir "$name.json")) {
        $i++
        $name = "$BaseName-$i"
    }

    Join-Path $Dir "$name.json"
}

# ============================================================
# Initialization
# ============================================================

$InputPath = Resolve-FullPath $InputPath
$OutputDir = Resolve-FullPath $OutputDir

Ensure-Directory $OutputDir

$totalLines   = 0
$filesWritten = 0
$failures     = 0

# UTF-8 encoding without BOM for output files
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ============================================================
# Main processing loop
# ============================================================

Get-Content -LiteralPath $InputPath -Encoding UTF8 | ForEach-Object {

    $line = $_
    $totalLines++

    try {
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) {
            return
        }

        # Parse JSON
        $obj = $line | ConvertFrom-Json -ErrorAction Stop

        # Repair any broken UTF-8 strings recursively
        Repair-ObjectStrings $obj | Out-Null

        if (-not $obj.url) {
            throw "Missing url field"
        }

        # Normalize URL
        $urlClean = Remove-QueryAndFragment $obj.url

        # Determine routing folder
        $route = Get-Route $urlClean

        # Extract relative filename portion
        $relative = ""
        if ($route.Prefix.Length -gt 0 -and $urlClean.StartsWith($route.Prefix)) {
            $relative = $urlClean.Substring($route.Prefix.Length)
        }

        # Determine base filename
        if ([string]::IsNullOrWhiteSpace($relative)) {

            if ($route.Folder -eq "others") {
                # Friendly filename from full URL:
                # https://gafasaddictive.com/cordon-silicona-gafas
                # -> gafasaddictive.com_cordon-silicona-gafas

                $friendly = $urlClean

                if ($friendly.StartsWith("https://")) { $friendly = $friendly.Substring(8) }
                elseif ($friendly.StartsWith("http://")) { $friendly = $friendly.Substring(7) }

                $friendly = $friendly -replace '/', '_'

                if ([string]::IsNullOrWhiteSpace($friendly)) {
                    $friendly = "index"
                }

                $baseName = Sanitize-Filename $friendly
            }
            else {
                $baseName = "index"
            }
        }
        else {
            $baseName = Sanitize-Filename $relative
        }

        # Ensure destination folder exists
        $targetDir = Join-Path $OutputDir $route.Folder
        Ensure-Directory $targetDir

        # Resolve final output path
        $outPath = Get-UniqueFilePath $targetDir $baseName

        # Serialize object back to JSON
        $jsonOut = $obj | ConvertTo-Json -Depth 20

        # Write file as UTF-8 without BOM
        [System.IO.File]::WriteAllText($outPath, $jsonOut, $utf8NoBom)

        $filesWritten++
        Write-Verbose "Written: $outPath"
    }
    catch {
        $failures++
        Write-Warning "Failed on line $totalLines : $($_.Exception.Message)"
    }
}

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "Total lines   : $totalLines"
Write-Host "Files written : $filesWritten"
Write-Host "Failures      : $failures"
