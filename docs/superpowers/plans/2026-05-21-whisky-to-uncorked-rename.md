# Whisky → Crosswire Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all "Whisky"/"whisky" references from the Crosswire codebase, replacing with "Crosswire"/"Crosswire" equivalents, without breaking the build.

**Architecture:** Two phases — Phase 1 touches only user-visible text (no build impact, one commit); Phase 2 renames Swift types, files, directories, and the Xcode package in four sub-steps each ending with a CI build verify before continuing.

**Tech Stack:** Swift 6, Xcode project (project.pbxproj), SwiftPM (Package.swift), GitHub Actions, PowerShell for file content edits, bash for git operations.

---

## Phase 1 — User-visible references

### Task 1: GPL license headers in Swift files

**Files:**
- Modify: all 64 `.swift` files containing `This file is part of Whisky`

- [ ] **Step 1: Run bulk replacement**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'This file is part of Whisky') {
        \$c = \$c -replace 'This file is part of Whisky\.', 'This file is part of Crosswire.'
        \$c = \$c -replace 'Whisky is free software:', 'Crosswire is free software:'
        \$c = \$c -replace 'Whisky is distributed in the hope', 'Crosswire is distributed in the hope'
        \$c = \$c -replace 'along with Whisky\.', 'along with Crosswire.'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify — no remaining Whisky header references**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
Select-String -Pattern 'This file is part of Whisky' |
Select-Object Filename, LineNumber, Line
"
```

Expected: no output.

---

### Task 2: `.swiftlint.yml` header template

**Files:**
- Modify: `.swiftlint.yml`

- [ ] **Step 1: Update the GPL header template**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\.swiftlint.yml'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'This file is part of Whisky\.', 'This file is part of Crosswire.'
\$c = \$c -replace 'Whisky is free software:', 'Crosswire is free software:'
\$c = \$c -replace 'Whisky is distributed in the hope', 'Crosswire is distributed in the hope'
\$c = \$c -replace 'along with Whisky\.', 'along with Crosswire.'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\.swiftlint.yml' -Pattern 'Whisky'"
```

Expected: no output.

---

### Task 3: `Localizable.xcstrings` — English strings

**Files:**
- Modify: `Whisky/Localizable.xcstrings`

- [ ] **Step 1: Update all 10 English string values**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Whisky\Localizable.xcstrings'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'Install Whisky CLI\.\.\.', 'Install Crosswire CLI...'
\$c = \$c -replace 'Terminate Wine processes when Whisky closes', 'Terminate Wine processes when Crosswire closes'
\$c = \$c -replace 'Automatically check for Whisky updates', 'Automatically check for Crosswire updates'
\$c = \$c -replace 'Automatically check for WhiskyWine updates', 'Automatically check for CrosswireWine updates'
\$c = \$c -replace 'Manage Whisky''s required dependencies\.', \"Manage Crosswire's required dependencies.\"
\$c = \$c -replace 'Welcome to Whisky', 'Welcome to Crosswire'
\$c = \$c -replace 'Downloading WhiskyWine', 'Downloading CrosswireWine'
\$c = \$c -replace 'Installing WhiskyWine', 'Installing CrosswireWine'
\$c = \$c -replace 'New Version of WhiskyWine Available', 'New Version of CrosswireWine Available'
\$c = \$c -replace 'running WhiskyWine', 'running CrosswireWine'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify all 10 English values updated**

```powershell
powershell.exe -NoProfile -Command "
\$content = Get-Content 'D:\grubwire\Crosswire\Whisky\Localizable.xcstrings' -Raw | ConvertFrom-Json
\$content.strings.PSObject.Properties |
    Where-Object { \$_.Value.localizations.en.stringUnit.value -match 'Whisky' } |
    ForEach-Object { Write-Host \"\$(\$_.Name): \$(\$_.Value.localizations.en.stringUnit.value)\" }
"
```

Expected: no output (no remaining English Whisky values).

---

### Task 4: `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update non-attribution Whisky references**

Keep lines 5, 9, 41, 48 that refer to the upstream project (attribution). Update any that describe Crosswire as "Whisky":

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\README.md'
\$c = Get-Content \$path -Raw
# Only update 'Whisky was archived' context line that says Whisky as if it's this app
# Attribution lines (linking to Whisky-App/Whisky) are left intact
\$c = \$c -replace '- Whisky was archived in April 2025', '- Whisky (the upstream project) was archived in April 2025'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify and review** — open `README.md` and read it to confirm the remaining Whisky mentions are all attribution/historical context, not self-references.

---

### Task 5: `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`

**Files:**
- Modify: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`

- [ ] **Step 1: Update CONTRIBUTING.md**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\CONTRIBUTING.md'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'make a fork of Whisky', 'make a fork of Crosswire'
\$c = \$c -replace 'Whisky is built using', 'Crosswire is built using'
\$c = \$c -replace 'Every Whisky commit', 'Every Crosswire commit'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Update CODE_OF_CONDUCT.md Discord link text**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\CODE_OF_CONDUCT.md'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'Whisky Discord', 'Crosswire Discord'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 3: Verify**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\CONTRIBUTING.md','D:\grubwire\Crosswire\CODE_OF_CONDUCT.md' -Pattern 'Whisky' | Select-Object Filename, LineNumber, Line"
```

Expected: no output.

---

### Task 6: `.github/ISSUE_TEMPLATE/bug.yml`

**Files:**
- Modify: `.github/ISSUE_TEMPLATE/bug.yml`

- [ ] **Step 1: Update field id, label, and help text**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\.github\ISSUE_TEMPLATE\bug.yml'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'id: whisky-version', 'id: Crosswire-version'
\$c = \$c -replace 'What version of Whisky are you using\?', 'What version of Crosswire are you using?'
\$c = \$c -replace 'pressing `CMD \+ L` in Whisky', 'pressing `CMD + L` in Crosswire'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\.github\ISSUE_TEMPLATE\bug.yml' -Pattern 'Whisky|whisky' | Select-Object LineNumber, Line"
```

Expected: no output.

---

### Task 7: `.github/workflows/wine-update-check.yml`

**Files:**
- Modify: `.github/workflows/wine-update-check.yml`

- [ ] **Step 1: Update checklist item in issue body**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\.github\workflows\wine-update-check.yml'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'WhiskyWineInstaller\.parseGcenxTag', 'CrosswireWineInstaller.parseGcenxTag'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\.github\workflows\wine-update-check.yml' -Pattern 'Whisky' | Select-Object LineNumber, Line"
```

Expected: no output.

---

### Task 8: Commit and push Phase 1

- [ ] **Step 1: Stage all changes**

```bash
cd "D:/grubwire/Crosswire"
git add -A
git status
```

Verify only the expected files are staged (no binary files, no unexpected changes).

- [ ] **Step 2: Commit**

```bash
git commit -m "Replace user-visible Whisky references with Crosswire

Updates GPL headers, localizable strings, README, CONTRIBUTING,
CODE_OF_CONDUCT, issue template, and workflow checklist text."
```

- [ ] **Step 3: Push and verify CI**

```bash
git push origin main
```

Then open https://github.com/grubwire/Crosswire/actions and confirm `Build` workflow passes on this commit before continuing to Phase 2.

---

## Phase 2A — Swift type renames (in-file only)

No file moves, no project.pbxproj changes in this step.

### Task 9: Rename Swift types and symbols

**Files:**
- Modify: `Whisky/Views/WhiskyApp.swift`
- Modify: `Whisky/Utils/WhiskyCmd.swift`
- Modify: `WhiskyCmd/Main.swift`
- Modify: `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`
- Modify: `WhiskyKit/Sources/WhiskyKit/Extensions/Bundle+Extensions.swift`
- Modify: `Whisky/Views/Setup/WhiskyWineDownloadView.swift`
- Modify: `Whisky/Views/Setup/WhiskyWineInstallView.swift`
- Modify: all files referencing the above types

- [ ] **Step 1: Rename `WhiskyApp` → `CrosswireApp` everywhere**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'WhiskyApp') {
        \$c = \$c -replace 'WhiskyApp', 'CrosswireApp'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 2: Rename `WhiskyCmd` class/struct → `CrosswireCmd`**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'WhiskyCmd') {
        \$c = \$c -replace 'WhiskyCmd', 'CrosswireCmd'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 3: Rename CLI struct `Whisky` → `Crosswire` in `WhiskyCmd/Main.swift`**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\WhiskyCmd\Main.swift'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'struct Whisky:', 'struct Crosswire:'
\$c = \$c -replace 'Whisky\.main\(\)', 'Crosswire.main()'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 4: Rename `WhiskyWineInstaller` and `WhiskyWineVersion` → `CrosswireWineInstaller` / `CrosswireWineVersion`**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'WhiskyWineInstaller|WhiskyWineVersion') {
        \$c = \$c -replace 'WhiskyWineInstaller', 'CrosswireWineInstaller'
        \$c = \$c -replace 'WhiskyWineVersion', 'CrosswireWineVersion'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 5: Rename view types `WhiskyWineDownloadView` / `WhiskyWineInstallView`**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'WhiskyWineDownloadView|WhiskyWineInstallView') {
        \$c = \$c -replace 'WhiskyWineDownloadView', 'CrosswireWineDownloadView'
        \$c = \$c -replace 'WhiskyWineInstallView', 'CrosswireWineInstallView'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 6: Rename `whiskyBundleIdentifier` → `CrosswireBundleIdentifier` everywhere**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'whiskyBundleIdentifier') {
        \$c = \$c -replace 'whiskyBundleIdentifier', 'CrosswireBundleIdentifier'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 7: Verify no Whisky type names remain in Swift files**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
Select-String -Pattern 'WhiskyApp|WhiskyCmd|WhiskyWineInstaller|WhiskyWineVersion|WhiskyWineDownloadView|WhiskyWineInstallView|whiskyBundleIdentifier' |
Select-Object Filename, LineNumber, Line
"
```

Expected: no output.

- [ ] **Step 8: Commit and push**

```bash
cd "D:/grubwire/Crosswire"
git add -A
git commit -m "Rename internal Swift types from Whisky to Crosswire

WhiskyApp→CrosswireApp, WhiskyCmd→CrosswireCmd, WhiskyWineInstaller→
CrosswireWineInstaller, WhiskyWineVersion→CrosswireWineVersion,
WhiskyWineDownloadView/InstallView→Crosswire*, whiskyBundleIdentifier→
CrosswireBundleIdentifier, CLI struct Whisky→Crosswire"
git push origin main
```

Wait for https://github.com/grubwire/Crosswire/actions `Build` to go green before continuing.

---

## Phase 2B — Source file renames + `project.pbxproj`

### Task 10: Rename source files with `git mv`

**Files:**
- Rename via git: 5 Swift files, 1 entitlements file, deletion of dead file

- [ ] **Step 1: Rename Swift source files**

```bash
cd "D:/grubwire/Crosswire"
git mv "Whisky/Views/WhiskyApp.swift" "Whisky/Views/CrosswireApp.swift"
git mv "Whisky/Utils/WhiskyCmd.swift" "Whisky/Utils/CrosswireCmd.swift"
git mv "Whisky/Views/Setup/WhiskyWineDownloadView.swift" "Whisky/Views/Setup/CrosswireWineDownloadView.swift"
git mv "Whisky/Views/Setup/WhiskyWineInstallView.swift" "Whisky/Views/Setup/CrosswireWineInstallView.swift"
git mv "WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift" "WhiskyKit/Sources/WhiskyKit/WhiskyWine/CrosswireWineInstaller.swift"
```

- [ ] **Step 2: Rename WhiskyThumbnail.entitlements**

```bash
git mv "WhiskyThumbnail/WhiskyThumbnail.entitlements" "WhiskyThumbnail/CrosswireThumbnail.entitlements"
```

- [ ] **Step 3: Delete dead `Whisky.entitlements` (build uses `Crosswire.entitlements` already)**

```bash
git rm "Whisky/Whisky.entitlements"
```

- [ ] **Step 4: Verify git staging looks correct**

```bash
git status
```

Expected: 5 renames for Swift files, 1 entitlements rename, 1 deletion. No unexpected changes.

---

### Task 11: Update `project.pbxproj` for file renames

**Files:**
- Modify: `Whisky.xcodeproj/project.pbxproj`

- [ ] **Step 1: Update file name references for renamed Swift files**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Whisky.xcodeproj\project.pbxproj'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'WhiskyApp\.swift', 'CrosswireApp.swift'
\$c = \$c -replace 'WhiskyCmd\.swift', 'CrosswireCmd.swift'
\$c = \$c -replace 'WhiskyWineDownloadView\.swift', 'CrosswireWineDownloadView.swift'
\$c = \$c -replace 'WhiskyWineInstallView\.swift', 'CrosswireWineInstallView.swift'
\$c = \$c -replace 'WhiskyWineInstaller\.swift', 'CrosswireWineInstaller.swift'
\$c = \$c -replace 'WhiskyThumbnail\.entitlements', 'CrosswireThumbnail.entitlements'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Remove the two `Whisky.entitlements` lines from `project.pbxproj`**

The dead file reference occupies two lines — one `PBXFileReference` entry and one group membership entry. Remove both:

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Whisky.xcodeproj\project.pbxproj'
\$lines = Get-Content \$path
\$filtered = \$lines | Where-Object { \$_ -notmatch '6E40495E29CCA19C006E3F1B.*Whisky\.entitlements' }
Set-Content \$path (\$filtered -join \`\`n) -NoNewline
Write-Host \`\"Removed \$(\$lines.Count - \$filtered.Count) lines\`\"
"
```

Expected output: `Removed 2 lines`

- [ ] **Step 3: Verify no remaining `Whisky.entitlements` or old Swift filenames in project.pbxproj**

```powershell
powershell.exe -NoProfile -Command "
Select-String -Path 'D:\grubwire\Crosswire\Whisky.xcodeproj\project.pbxproj' -Pattern 'WhiskyApp\.swift|WhiskyCmd\.swift|WhiskyWineDownloadView|WhiskyWineInstallView|WhiskyWineInstaller\.swift|Whisky\.entitlements|WhiskyThumbnail\.entitlements' |
Select-Object LineNumber, Line
"
```

Expected: no output.

- [ ] **Step 4: Commit and push**

```bash
cd "D:/grubwire/Crosswire"
git add -A
git commit -m "Rename Whisky* source files to Crosswire* equivalents

Renames 5 Swift files, WhiskyThumbnail.entitlements, removes dead
Whisky.entitlements (build already uses Crosswire.entitlements).
Updates all project.pbxproj file references to match."
git push origin main
```

Wait for `Build` CI green before continuing.

---

## Phase 2C — Package rename: `WhiskyKit` → `CrosswireKit`

### Task 12: Rename the Swift package directory and manifest

**Files:**
- Rename dir: `WhiskyKit/` → `CrosswireKit/`
- Rename dir: `WhiskyKit/Sources/WhiskyKit/` → `CrosswireKit/Sources/CrosswireKit/`
- Rename dir: `CrosswireKit/Sources/CrosswireKit/WhiskyWine/` → `CrosswireKit/Sources/CrosswireKit/CrosswireWine/`
- Modify: `CrosswireKit/Package.swift`

- [ ] **Step 1: Move top-level package directory**

```bash
cd "D:/grubwire/Crosswire"
git mv WhiskyKit CrosswireKit
```

- [ ] **Step 2: Move inner source directory**

```bash
git mv "CrosswireKit/Sources/WhiskyKit" "CrosswireKit/Sources/CrosswireKit"
```

- [ ] **Step 3: Move inner WhiskyWine subdirectory**

```bash
git mv "CrosswireKit/Sources/CrosswireKit/WhiskyWine" "CrosswireKit/Sources/CrosswireKit/CrosswireWine"
```

- [ ] **Step 3b: Move inner Whisky subdirectory (bottle/data models)**

```bash
git mv "CrosswireKit/Sources/CrosswireKit/Whisky" "CrosswireKit/Sources/CrosswireKit/Crosswire"
```

- [ ] **Step 4: Update `Package.swift` — package name and target names**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\CrosswireKit\Package.swift'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'name: \"WhiskyKit\"', 'name: \"CrosswireKit\"'
\$c = \$c -replace '\"WhiskyKit\"', '\"CrosswireKit\"'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 5: Verify Package.swift has no WhiskyKit**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\CrosswireKit\Package.swift' -Pattern 'WhiskyKit'"
```

Expected: no output.

---

### Task 13: Update all `import WhiskyKit` statements

**Files:**
- Modify: 27 Swift files (all containing `import WhiskyKit`)

- [ ] **Step 1: Bulk replace**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
ForEach-Object {
    \$c = Get-Content \$_.FullName -Raw
    if (\$c -match 'import WhiskyKit') {
        \$c = \$c -replace 'import WhiskyKit', 'import CrosswireKit'
        Set-Content \$_.FullName \$c -NoNewline
    }
}
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "
Get-ChildItem -Recurse 'D:\grubwire\Crosswire' -Include '*.swift' |
Select-String -Pattern 'import WhiskyKit' |
Select-Object Filename, LineNumber
"
```

Expected: no output.

---

### Task 14: Update `project.pbxproj` for package rename

**Files:**
- Modify: `Whisky.xcodeproj/project.pbxproj`

- [ ] **Step 1: Replace `WhiskyKit` package references**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Whisky.xcodeproj\project.pbxproj'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'WhiskyKit', 'CrosswireKit'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

Note: this replaces ALL `WhiskyKit` occurrences in the file. At this point in the plan `WhiskyKit` only refers to the package — target names (`Whisky`, `WhiskyCmd`, `WhiskyThumbnail`) do not contain `WhiskyKit`, so there is no risk of over-replacement.

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "
Select-String -Path 'D:\grubwire\Crosswire\Whisky.xcodeproj\project.pbxproj' -Pattern 'WhiskyKit' |
Select-Object LineNumber, Line
"
```

Expected: no output.

---

### Task 15: Update `dependabot.yml`

**Files:**
- Modify: `.github/dependabot.yml`

- [ ] **Step 1: Update package directory reference**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\.github\dependabot.yml'
\$c = Get-Content \$path -Raw
\$c = \$c -replace '/WhiskyKit', '/CrosswireKit'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify**

```powershell
powershell.exe -NoProfile -Command "Select-String -Path 'D:\grubwire\Crosswire\.github\dependabot.yml' -Pattern 'WhiskyKit'"
```

Expected: no output.

- [ ] **Step 3: Commit and push**

```bash
cd "D:/grubwire/Crosswire"
git add -A
git commit -m "Rename WhiskyKit package to CrosswireKit

Renames directory, Sources subdirectory, WhiskyWine→CrosswireWine
subdir, updates Package.swift, all import statements, project.pbxproj
package references, and dependabot.yml directory."
git push origin main
```

Wait for `Build` CI green before continuing.

---

## Phase 2D — Top-level directory renames

### Task 16: Rename directories with `git mv`

**Files:**
- Rename: `Whisky/` → `Crosswire/`
- Rename: `WhiskyCmd/` → `CrosswireCmd/`
- Rename: `WhiskyThumbnail/` → `CrosswireThumbnail/`
- Rename: `Whisky.xcodeproj/` → `Crosswire.xcodeproj/`

- [ ] **Step 1: Rename directories**

```bash
cd "D:/grubwire/Crosswire"
git mv Whisky Crosswire
git mv WhiskyCmd CrosswireCmd
git mv WhiskyThumbnail CrosswireThumbnail
git mv Whisky.xcodeproj Crosswire.xcodeproj
```

- [ ] **Step 2: Verify git tracks all moves**

```bash
git status | head -40
```

Expected: many renames listed (Whisky/... → Crosswire/..., etc.), no unexpected deletions.

---

### Task 17: Update `project.pbxproj` for directory renames

**Files:**
- Modify: `Crosswire.xcodeproj/project.pbxproj` (already at new path after Task 16)

- [ ] **Step 1: Update group path and target name references**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Crosswire.xcodeproj\project.pbxproj'
\$c = Get-Content \$path -Raw

# Directory path references (e.g. 'path = Whisky;')
\$c = \$c -replace 'path = Whisky;', 'path = Crosswire;'
\$c = \$c -replace 'path = WhiskyCmd;', 'path = CrosswireCmd;'
\$c = \$c -replace 'path = WhiskyThumbnail;', 'path = CrosswireThumbnail;'

# Target names
\$c = \$c -replace 'name = Whisky;', 'name = Crosswire;'
\$c = \$c -replace 'name = WhiskyCmd;', 'name = CrosswireCmd;'
\$c = \$c -replace 'name = WhiskyThumbnail;', 'name = CrosswireThumbnail;'

# productName
\$c = \$c -replace 'productName = Whisky;', 'productName = Crosswire;'
\$c = \$c -replace 'productName = WhiskyCmd;', 'productName = CrosswireCmd;'
\$c = \$c -replace 'productName = WhiskyThumbnail;', 'productName = CrosswireThumbnail;'

# Product file references (the .app and .appex in BUILT_PRODUCTS_DIR)
\$c = \$c -replace 'path = Whisky\.app;', 'path = Crosswire.app;'
\$c = \$c -replace 'Whisky\.app \*/', 'Crosswire.app */'
\$c = \$c -replace 'WhiskyThumbnail\.appex', 'CrosswireThumbnail.appex'
\$c = \$c -replace 'WhiskyCmd \*/', 'CrosswireCmd */'
\$c = \$c -replace 'path = WhiskyCmd;', 'path = CrosswireCmd;'

# Build phase name
\$c = \$c -replace 'Embed WhiskyCmd', 'Embed CrosswireCmd'

# Build configuration list comments
\$c = \$c -replace 'PBXNativeTarget \"Whisky\"', 'PBXNativeTarget \"Crosswire\"'
\$c = \$c -replace 'PBXNativeTarget \"WhiskyCmd\"', 'PBXNativeTarget \"CrosswireCmd\"'
\$c = \$c -replace 'PBXNativeTarget \"WhiskyThumbnail\"', 'PBXNativeTarget \"CrosswireThumbnail\"'

# PBXProject name
\$c = \$c -replace 'PBXProject \"Whisky\"', 'PBXProject \"Crosswire\"'

# Bundle identifier for thumbnail (WhiskyThumbnail → CrosswireThumbnail)
\$c = \$c -replace 'app\.Crosswire\.Crosswire\.WhiskyThumbnail', 'app.Crosswire.Crosswire.CrosswireThumbnail'

# Bundle identifier for CLI (UncorkCmd → CrosswireCmd — fixing the existing typo too)
\$c = \$c -replace 'app\.Crosswire\.UncorkCmd', 'app.Crosswire.CrosswireCmd'

# remoteInfo
\$c = \$c -replace 'remoteInfo = WhiskyThumbnail;', 'remoteInfo = CrosswireThumbnail;'

# Build settings with directory-qualified paths (CRITICAL — these break the build if missed)
\$c = \$c -replace 'CODE_SIGN_ENTITLEMENTS = Whisky/', 'CODE_SIGN_ENTITLEMENTS = Crosswire/'
\$c = \$c -replace 'DEVELOPMENT_ASSET_PATHS = \"\"Whisky/', 'DEVELOPMENT_ASSET_PATHS = \"\"Crosswire/'
\$c = \$c -replace 'INFOPLIST_FILE = Whisky/', 'INFOPLIST_FILE = Crosswire/'

Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Verify no remaining Whisky target/path references**

```powershell
powershell.exe -NoProfile -Command "
Select-String -Path 'D:\grubwire\Crosswire\Crosswire.xcodeproj\project.pbxproj' -Pattern 'Whisky' |
Select-Object LineNumber, Line
"
```

Expected: no output.

---

### Task 18: Update `crowdin.yml` and scheme files

**Files:**
- Modify: `crowdin.yml`
- Modify: `Crosswire.xcodeproj/xcshareddata/xcschemes/Whisky.xcscheme` (rename + content)

- [ ] **Step 1: Update `crowdin.yml` source/translation paths**

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\crowdin.yml'
\$c = Get-Content \$path -Raw
\$c = \$c -replace '/Whisky/Localizable\.xcstrings', '/Crosswire/Localizable.xcstrings'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 2: Rename `Whisky.xcscheme` and update its contents**

```bash
cd "D:/grubwire/Crosswire"
git mv "Crosswire.xcodeproj/xcshareddata/xcschemes/Whisky.xcscheme" "Crosswire.xcodeproj/xcshareddata/xcschemes/CrosswireLegacy.xcscheme"
```

Then update any `Whisky` references inside the moved scheme file:

```powershell
powershell.exe -NoProfile -Command "
\$path = 'D:\grubwire\Crosswire\Crosswire.xcodeproj\xcshareddata\xcschemes\CrosswireLegacy.xcscheme'
\$c = Get-Content \$path -Raw
\$c = \$c -replace 'BlueprintName = \"Whisky\"', 'BlueprintName = \"Crosswire\"'
\$c = \$c -replace 'BuildableName = \"Whisky\.app\"', 'BuildableName = \"Crosswire.app\"'
Set-Content \$path \$c -NoNewline
Write-Host 'Done'
"
```

- [ ] **Step 3: Update remaining scheme files for `WhiskyCmd` and `WhiskyThumbnail`**

```bash
cd "D:/grubwire/Crosswire"
git mv "Crosswire.xcodeproj/xcshareddata/xcschemes/WhiskyCmd.xcscheme" "Crosswire.xcodeproj/xcshareddata/xcschemes/CrosswireCmd.xcscheme"
git mv "Crosswire.xcodeproj/xcshareddata/xcschemes/WhiskyThumbnail.xcscheme" "Crosswire.xcodeproj/xcshareddata/xcschemes/CrosswireThumbnail.xcscheme"
```

```powershell
powershell.exe -NoProfile -Command "
foreach (\$name in @('CrosswireCmd', 'CrosswireThumbnail')) {
    \$path = \"D:\grubwire\Crosswire\Crosswire.xcodeproj\xcshareddata\xcschemes\\${name}.xcscheme\"
    \$c = Get-Content \$path -Raw
    \$c = \$c -replace 'WhiskyCmd', 'CrosswireCmd'
    \$c = \$c -replace 'WhiskyThumbnail', 'CrosswireThumbnail'
    Set-Content \$path \$c -NoNewline
}
Write-Host 'Done'
"
```

---

### Task 19: Final verification sweep

- [ ] **Step 1: Check for any remaining Whisky references across all tracked files**

```bash
cd "D:/grubwire/Crosswire"
git grep -i "whisky" -- "*.swift" "*.yml" "*.yaml" "*.md" "*.xcscheme" "*.pbxproj" "*.plist" "*.strings" "*.xcstrings" "*.entitlements"
```

Expected output: only the attribution lines in `README.md` (lines referencing `Whisky-App/Whisky` upstream).

- [ ] **Step 2: If any unexpected hits appear**, fix them manually before committing.

---

### Task 20: Commit and push Phase 2D

- [ ] **Step 1: Commit**

```bash
cd "D:/grubwire/Crosswire"
git add -A
git commit -m "Rename all Whisky directories, targets, and schemes to Crosswire

Renames Whisky/→Crosswire/, WhiskyCmd/→CrosswireCmd/, WhiskyThumbnail/→
CrosswireThumbnail/, Whisky.xcodeproj→Crosswire.xcodeproj. Updates all
project.pbxproj target names, paths, product names, and bundle IDs.
Renames scheme files and updates crowdin.yml source path."
git push origin main
```

- [ ] **Step 2: Verify CI passes**

Open https://github.com/grubwire/Crosswire/actions and confirm `Build` workflow passes.

- [ ] **Step 3: Final rename check**

```bash
cd "D:/grubwire/Crosswire"
git grep -i "whisky" -- "*.swift" "*.yml" "*.yaml" "*.md" "*.xcscheme" "*.pbxproj" "*.plist" "*.strings" "*.xcstrings" "*.entitlements"
```

Only expected output:
```
README.md:Crosswire is a maintained fork of [Whisky](https://github.com/Whisky-App/Whisky)...
README.md:- Whisky (the upstream project) was archived in April 2025
README.md:- [Whisky](https://github.com/Whisky-App/Whisky) by Isaac Marovitz...
README.md:MIT - same as Whisky upstream.
```
