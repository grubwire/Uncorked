# Recipe System Architecture Research: CrossOver vs Open-Source

## 1. CrossOver Source Findings

The CrossOver source tarball at D:\crossover\crossover-sources-26.1.0\sources\ contains Wine base library and utilities but NO recipe system code. This is expected:

- No files named crosstie.*, bottle.*, template.*, or recipe.*
- No strings referencing game-specific templates (swg, wow, eve, etc.)
- No configuration files (.json, .yaml, .xml) defining per-app prerequisites
- cabextract/ is a utility for extracting .cab archives, not a recipe system
- wine/dlls/msi/ handles MSI install events but contains no per-app logic

Conclusion: CrossOver's recipe system (their proprietary "CrossTie" or bottle templates) is NOT in the GPL Wine source tarball. It lives in their proprietary GUI/installer frontend, which they do not ship as open source. The Wine codebase itself is generic and doesn't encode game-specific workarounds.

## 2. Open-Source Recipe Patterns

### Winetricks (Shell-Based Verb System)
- Storage: Verbs are shell functions defined inline in a single shell script
- Format: w_<verbname>() function definitions with dependencies via w_call() invocations
- Metadata: Global variables (W_PACKAGE, W_ARCH, W_PLATFORM) track context
- Actions: Download files, override DLLs, modify registry via w_try_regedit(), conditional execution per architecture
- Discovery: No centralized recipe list; verbs enumerated by parsing function definitions

### Lutris (YAML Install Scripts)
- Storage: Per-game YAML files stored in a central repository
- Key Fields: version, slug, runner, game_name, script, service, service_appid, variables, requires, extends
- Script Format: List of ordered tasks (download, extract, run installer, set registry, etc.)
- Metadata: Variables for substitution, dependency declarations (requires/extends), service integration (Steam, GOG)
- Discovery: Slug-based lookup; installer retrieved from central metadata repository

### Bottles (Python Dataclass Configuration)
- Storage: BottleConfig dataclass persisted in Python config files; dependencies stored as part of bottle state
- Key Fields: Architecture, Windows version, Runner, DXVK/VKD3D versions, installed_dependencies list
- DependencyManager: Resolves prerequisites, filters by architecture, executes ordered actions
- Actions: Download/extract, run installers, register DLLs, modify registry, copy system files
- Tracking: Persists installation status and uninstaller information per dependency
- Model: bottles/backend/managers/dependency.py shows modular dependency installation with prerequisite resolution

### Heroic Games Launcher (Minimal Recipe Support)
- Approach: Leverages external tools (Wine, Proton, CrossOver on macOS)
- Per-Game Configuration: Game install/uninstall/repair/move via native APIs; no custom recipe system
- Discovery Method: Game slug mapping from Epic Games Store, GOG, Amazon Games
- No Custom Prerequisites: Relies on configured runner (Proton/Wine) and system libraries

## 3. Recommended Pattern for Crosswire

Adopt a hybrid approach combining Winetricks simplicity with Bottles modularity:

### Recipe Storage
- Location: In-repo JSON files at Crosswire/Resources/recipes/ with naming <game-slug>.recipe.json
- Fallback: For v1.0.8, store recipes in hardcoded directory; upgrade to network fetching (data.grubwire.io) in v1.0.9
- Detection: SHA-256 hash of installer exe matched against recipe metadata; fallback to filename heuristics

### Recipe JSON Schema

{
  "version": 1,
  "id": "swg-legends",
  "name": "Star Wars Galaxies Legends",
  "engine_minimum": "1.0.8",
  "description": "Pre-requisites for SWG Legends private server",
  "game_signatures": [
    {
      "hash_sha256": "abc123...",
      "filename_pattern": "swg_legends_installer_*.exe"
    }
  ],
  "supported_architectures": ["x86_64"],
  "prerequisites": [
    {
      "id": "vcrun2015",
      "type": "winetricks_verb",
      "verb": "vcrun2015",
      "required": true,
      "description": "Visual C++ 2015 Redistributable"
    },
    {
      "id": "dotnet48",
      "type": "winetricks_verb",
      "verb": "dotnet48",
      "required": false,
      "description": ".NET Framework 4.8"
    }
  ],
  "environment_overrides": {
    "DXVK_MEMORY_ALLOCATOR": "page"
  },
  "dll_overrides": {
    "d3d9": "native",
    "ddraw": "native"
  }
}

### Recipe Application Workflow

1. Detection Phase (on app first run):
   - User selects installer executable
   - Crosswire computes SHA-256 hash and checks recipe database
   - Falls back to filename pattern matching if no hash match

2. Prerequisite Resolution Phase:
   - Load recipe JSON for matching game
   - Recursively resolve transitive dependencies
   - Validate architecture compatibility

3. Application Phase (before user's installer runs):
   - Execute each winetricks verb in order
   - Copy files to appropriate Wine prefix locations
   - Apply registry tweaks via wine reg add
   - Set environment variables and DLL overrides in bottle config

4. Fallback Behavior:
   - If recipe application fails, warn user but allow them to proceed with manual installation
   - Log which prerequisites failed for debugging

## 4. Effort Estimate

### Small (v1.0.8, 1-2 weeks)
- Implement recipe JSON schema and validator (300 lines Swift)
- Add SHA-256 hash computation for installer detection (100 lines)
- Build winetricks verb executor wrapper (200 lines)
- Hardcode 5-10 high-demand recipes (SWG Legends, WoW, EVE, Diablo 2, SWTOR)
- UI: Simple "Detected [Game Name]. Apply recommended settings?" dialog

### Medium (v1.0.9, 2-3 weeks, if advancing beyond v1.0.8)
- Network recipe fetching from data.grubwire.io with local caching (400 lines)
- Registry editor for custom tweaks (200 lines)
- Dependency resolution engine with cycle detection (300 lines)
- File copy and font installation support (200 lines)
- Logging and rollback mechanism for failed prerequisites (150 lines)
- Recipe authoring UI for community contributions (500 lines)

## 5. Final Recommendation (250 words)

For Crosswire v1.0.8 (near-term release), implement a minimal JSON-based recipe system focused on solving the most common prerequisites: Visual C++ runtimes, .NET Framework, DirectX, and per-game registry tweaks.

Specific approach:

1. Storage: Commit 5-10 high-demand game recipes as JSON files in the repository under Crosswire/Resources/recipes/. Use SHA-256 hash of the installer executable as the primary lookup key; fall back to filename pattern matching.

2. Schema: Define recipes with a simple structure: metadata (id, name, game signatures), prerequisite list (winetricks verbs, file copies, registry edits), and optional DLL overrides and environment variables.

3. Execution: Before launching the user's installer, query the recipe database. If a match is found, present a "Recommended Prerequisites" dialog. Use the Crosswire wrapper already calling winetricks to execute verbs (vcrun*, dotnet*, dxsetup, etc.). For registry and file operations, use wine built-in commands or Swift file operations.

4. Fallback: If recipe application fails, log the error and allow the user to proceed manually. This ensures graceful degradation.

5. No network required for v1.0.8: Embed recipes in the app bundle. This avoids infrastructure setup and keeps the release small.

Effort: 1-2 weeks. The winetricks infrastructure is already in place; recipes add orchestration and detection logic on top.

Why this works: Lutris and Bottles both ship per-app recipes as data files, not code. Winetricks verbs are mature and well-tested. By reusing winetricks and adding minimal wrapper logic, Crosswire solves 80% of the per-game prerequisite problem with 20% of the effort of a full recipe engine.
