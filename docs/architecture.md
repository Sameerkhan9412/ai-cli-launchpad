# Architecture

## Goal

Make "use Claude Code with provider X" a single command that is **safe to re-run**: no hand-edited env vars, no clobbered config, no leaked keys.

## Layers

```mermaid
flowchart TB
    subgraph Entry["Entry scripts (thin)"]
        S["Start-ClaudeWithMiMo.ps1<br/>daily launcher"]
        C["Configure-ClaudeWithMiMo.ps1<br/>one-time global setup"]
    end
    subgraph Lib["lib/ (pure-ish, unit tested)"]
        M["MiMo.ps1<br/>endpoints · plan detection · key/URL guard<br/>model catalog · Claude env"]
        MS["ModelSelector.ps1<br/>menu · aliases · saved default"]
        CO["Common.ps1<br/>.env read/write · BOM-free writes<br/>settings merge · onboarding flag · backups"]
    end
    subgraph State["State on disk"]
        E[".env (key)"]
        P["preferences.json (model)"]
        ST["~/.claude/settings.json"]
        O["~/.claude.json"]
    end
    S --> M & MS & CO
    C --> M & MS & CO
    CO --> E & ST & O
    MS --> P
    S --> CL["claude CLI"] --> API["MiMo Anthropic-compatible API"]
```

**Rule:** decisions live in `lib/` functions that take inputs and return values (easy to test). Entry scripts only wire them together and print.

## Launch sequence

```mermaid
sequenceDiagram
    actor U as User
    participant L as Start-ClaudeWithMiMo
    participant K as Resolve-MiMoApiKey
    participant P as Resolve-MiMoPlan
    participant G as Get-MiMoKeyPlanConflict
    participant M as Resolve-LaunchModel
    participant F as Set-ClaudeUserSettings
    participant C as claude

    U->>L: run (optional -Model / -Plan / -DryRun)
    L->>K: param > env > .env > legacy names
    K-->>L: key + source
    L->>P: key prefix (or forced plan)
    P-->>L: PlanId + BaseUrl + reason
    L->>G: key vs BaseUrl
    alt mismatch
        G-->>L: error text
        L-->>U: exit 1 with fix hint
    end
    L->>M: bound model / saved default / menu
    M-->>L: main + fast model
    alt -DryRun
        L-->>U: print config, exit 0
    end
    L->>F: merge env + cache settings (backup first)
    L->>C: claude --model <main> [args]
```

## Design decisions

| Decision | Why |
|---|---|
| Detect endpoint from key prefix | Token Plan and pay-as-you-go keys only work on their own URL; the mismatch error from the API does not say that |
| Refuse mismatches locally | Fails fast with an actionable message instead of a 400/401 |
| Merge `settings.json`, never overwrite | Users keep permissions, hooks, status line, other env vars |
| Edit `~/.claude.json` as text | It holds project trust and MCP servers; re-serializing risks changing it (PS 5.1 JSON quirks, depth limits) |
| BOM-free UTF-8 writes | Windows PowerShell 5.1 `-Encoding utf8` adds a BOM; Node's `JSON.parse` rejects it |
| Main vs fast model slots | Heavy reasoning on Pro, cheap background/subagent calls on Flash |
| Saved default per provider in `preferences.json` | Zero-prompt daily launches, one keypress to change |
| `-DryRun` | Safe to demo, debug and smoke-test in CI without a real key or `claude` installed |
| Honor `CLAUDE_CONFIG_DIR` | Matches Claude Code behaviour; also lets tests use a temp folder |

## Adding another provider

1. `lib/<Provider>.ps1` — endpoint(s), key resolution, conflict check, catalog, `Get-<Provider>ClaudeEnv`.
2. `Start-ClaudeWith<Provider>.ps1` — copy the MiMo launcher shape; call your lib.
3. `tests/<Provider>.Tests.ps1` — cover detection, conflicts, catalog, env.
