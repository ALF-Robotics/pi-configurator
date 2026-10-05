# pi-configurator

<div align="center">
  <b>Interactive scripts to create and update provider profiles for <a href="https://pi.dev/">pi-code</a></b>
  <br>
  <sub>bash + PowerShell · non-destructive merge · one-liner provisioning</sub>
</div>

<div align="center">

[![license](https://img.shields.io/github/license/ALF-Robotics/pi-configurator?style=flat&label=license)](LICENSE)
[![tag](https://img.shields.io/github/v/tag/ALF-Robotics/pi-configurator?style=flat&label=release)](https://github.com/ALF-Robotics/pi-configurator/releases)
[![last-commit](https://img.shields.io/github/last-commit/ALF-Robotics/pi-configurator?style=flat)](https://github.com/ALF-Robotics/pi-configurator/commits/main)
[![stars](https://img.shields.io/github/stars/ALF-Robotics/pi-configurator?style=flat&label=stars)](https://github.com/ALF-Robotics/pi-configurator/stargazers)
[![EULA](https://img.shields.io/badge/EULA-v1.1-informational)](EULA.en.md)
[![EULA-it](https://img.shields.io/badge/EULA-IT-informational)](EULA.md)
[![type](https://img.shields.io/badge/type-utility-blueviolet)](#-what-it-does)
[![target](https://img.shields.io/badge/target-pi%20%28pi--coding--agent%29-ff69d4)](https://pi.dev/)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#-files)
[![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)](pi-conf.sh)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-012456)](pi-conf.ps1)
[![dep](https://img.shields.io/badge/dep-jq-c0c0c0)](#-dependencies)

</div>

<p align="center">
  <a href="https://alf-robotics.github.io/pi-configurator/"><b>🌐 Support page</b></a>
  &nbsp;·&nbsp;
  🇮🇹 <a href="README.md"><b>Italiano</b></a> &nbsp;·&nbsp; 🇬🇧 <b>English</b>
</p>

---

> [!IMPORTANT]
> The code is licensed under the [MIT License](LICENSE). Use of the script as an
> operational tool — including the credentials entrusted to it — is governed by the
> terms of the [EULA](EULA.en.md) v1.1, which **coexists** with MIT and does not
> replace it.
>
> This English version is a convenience translation with no autonomous legal
> effect. The **Italian original** ([EULA.md](EULA.md)) is the authoritative one
> and prevails in case of any divergence.

## 📋 Table of contents

- [Quick install](#-quick-install)
- [Let your AI set it up](#-let-your-ai-set-it-up)
- [What it does](#-what-it-does)
- [How the merge works](#-how-the-merge-works)
- [Non-interactive use](#-non-interactive-use)
- [Dependencies](#-dependencies)
- [Security](#-security)
- [Tests](#-tests)
- [Known limits](#-known-limits)

---

## 🚀 Quick install

**Tool only**, if you will then use it by hand or interactively:

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.ps1 | iex
```

**Tool and provider together**, for provisioning:

```bash
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.sh \
  | sh -s -- \
      --endpoint https://api.server.example \
      --api anthropic \
      --model MLR-3 \
      --key-env MLR_API_KEY
```

It installs into `~/.local/bin` (Windows: `%USERPROFILE%\.pi-configurator`) and
verifies every downloaded file with its **SHA256** before writing: if the hash
does not match, the install stops without touching anything.

> [!TIP]
> **Pin the version.** `main` can change at any moment, a tag cannot:
> `curl -fsSL .../main/install.sh | sh -s -- --ref v0.3.0`

<details>
<summary><b>Windows installer (PowerShell), full options</b></summary>

```powershell
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.ps1 | iex -args @(
    '-Endpoint','https://api.server.example',
    '-Api','anthropic',
    '-Model','MLR-3',
    '-KeyEnv','MLR_API_KEY'
)
```

</details>

### Installer options

| Installer | Role | Provider flags |
|---|---|---|
| `install.sh` / `install.ps1` | download and verify the tool | after `--` |
| `install-provider.sh` / `.ps1` | install **and** configure | top-level, no `--` |

Both accept `--ref`, `--prefix`, `--dry-run`, `--no-verify`.
`install-provider` additionally accepts the provider flags (`--endpoint`,
`--model`, `--key-env`, …) and **rejects** a missing `--endpoint` or `--model`
*before* installing anything.

`install-provider` also verifies the hash of `install.sh` before running it: that
is code about to execute, not just a file to drop into `/usr/local/bin`.

---

## 🤖 Let your AI set it up

If you use a coding assistant (pi, Claude Code, Codex, …) you can skip the
copy-paste: paste this prompt and the assistant installs and configures the
provider, **verifying the download before running it**.

<details open>
<summary><b>Ready-to-use prompt</b></summary>

```text
Install pi-configurator and configure the provider on this host.

First read README.md and the "Non-interactive use" section: flag names and
procedures are defined there, do not improvise them.

Procedure, with no deviations:

1. Download install-provider.sh from the TAG v0.3.1, never from main, into a
   temporary directory. Pin the tag: main can change at any moment.
2. Verify the SHA256 of the downloaded file against the entry in SHA256SUMS
   fetched from the SAME ref (v0.3.1), not from main. If it does not match,
   STOP and report it. Do not use --no-verify, and never run a file you have
   not verified.
3. Ask me only for what you cannot infer: endpoint, model id, and the name of
   the environment variable holding the API key. Do not ask me for the key in
   clear.
4. Run the installer with:
       --ref v0.3.1
       --endpoint <endpoint>
       --api anthropic
       --model <model-id>
       --key-env <VAR_NAME>
   Never use --key: with --key-env the script writes
   "apiKey": "$<VAR_NAME>" and pi resolves it from the environment on every
   request, so the credential never lands on disk in clear.
5. Verify with:  pi auth check --provider <profile-name> --json
6. Show me the resulting models.json with the apiKey masked.

Constraints: do not modify ~/.pi/agent/settings.json unless I explicitly ask.
If jq is missing, install it or stop and tell me; do not work around it.
Before writing models.json, remember a backup is created at
models.json.bak: if the file already exists and holds other providers, none
of them may be lost.
```

</details>

The same prompt in Italian, for those who prefer to give the instructions to
their own assistant in Italian:

<details>
<summary><b>Same prompt, in Italian</b></summary>

```text
Installa pi-configurator e configura il provider su questo host.

Prima di tutto leggi README.md e la sezione "Uso non interattivo": i nomi dei
flag e le procedure sono definiti li', non improvvisarli.

Procedura, senza deviazioni:

1. Scarica install-provider.sh dal TAG v0.3.1, mai da main, in una directory
   temporanea. Pinna il tag: main puo' cambiare in qualsiasi momento.
2. Verifica lo SHA256 del file scaricato confrontandolo con la voce in
   SHA256SUMS scaricata dallo STESSO ref (v0.3.1), non da main. Se non
   corrisponde, FERMATI e segnalalo. Non usare --no-verify e non eseguire
   un file non verificato.
3. Chiedimi solo cio' che non puoi dedurre: endpoint, model id, e il nome della
   variabile d'ambiente che contiene la API key. Non chiedermi la chiave in
   chiaro.
4. Esegui l'installer con:
       --ref v0.3.1
       --endpoint <endpoint>
       --api anthropic
       --model <model-id>
       --key-env <NOME_VARIABLE>
   Non usare MAI --key: con --key-env lo script scrive
   "apiKey": "$<NOME_VARIABLE>" e pi la risolve dall'ambiente a ogni richiesta,
   quindi la credenziale non finisce mai su disco in chiaro.
5. Verifica con:  pi auth check --provider <nome-profilo> --json
6. Mostrami il models.json risultante con la apiKey mascherata.

Vincoli: non modificare ~/.pi/agent/settings.json se non te lo chiedo
esplicitamente. Se jq manca, installalo o fermati e dimmelo, non aggirarlo.
Prima di scrivere models.json, ricorda che ne viene creato un backup in
models.json.bak: se il file esiste gia' e contiene altri provider, non deve
perderne nessuno.
```

</details>

> [!NOTE]
> The prompt is written to be **pasted as-is**. If you modify it, keep the
> three constraints that make it safe: SHA256 verification before running,
> `--key-env` instead of `--key`, and no changes to `settings.json` without an
> explicit request.

---

## 🎯 What it does

The scripts write to `~/.pi/agent/models.json`
(Windows: `%USERPROFILE%\.pi\agent\models.json`) with a **merge**, not an
overwrite: they add the provider without touching the others, and update an
existing profile **field by field**, preserving `apiKey`, `promptCache`,
`headers`, `compat`, `cost` and any extra models.
A backup is written to `models.json.bak` before every save.

### The 8 questions

| # | Question | Default |
|---|---|---|
| 1 | **Endpoint URL** (e.g. `https://api.server.example`) | — |
| 2 | **API standard** — friendly name mapped automatically | `anthropic` |
| 3 | **Model ID** (e.g. `MLR-3`, `claude-sonnet-4-5`) | — |
| 4 | **Profile name** (provider name in pi) | sanitized model id |
| 5 | **API key** — optional; leave empty to configure later with `/login` | — |
| 6 | **Extended reasoning?** | `y` |
| 7 | **Context window** | `512000` |
| 8 | **Max output tokens** | `32768` |

<details>
<summary><b>API standard: how the friendly name is translated</b></summary>

| You write | You get |
|---|---|
| `anthropic` | `anthropic-messages` |
| `openai` | `openai-completions` |
| `responses` | `openai-responses` |
| `google` | `google-generative-ai` |
| `mistral`, `bedrock`, `vertex`, `codex`, `azure` | the matching name |
| `<other>` | passed through to pi **verbatim** |

</details>

The API key is echoed as `*` while typing or pasting, to give visual feedback,
and backspace works normally.

> [!WARNING]
> **`maxTokens` includes reasoning tokens.** With `anthropic-messages` the cap
> applies to the completion **as a whole**: with reasoning enabled the `32768`
> default is the reasoning budget **plus** the answer. That is why the default is
> `32768` and not `16384`: the latter suits a model without reasoning, and with
> reasoning at `y` (the default) it would cut your long answers off **silently,
> with no error**.

### Final flow

1. Prints a JSON preview of the provider
2. If the profile name already exists → asks for overwrite confirmation
3. Asks for final confirmation
4. Merges with `jq` (bash) or `ConvertFrom-Json`/`ConvertTo-Json` (PowerShell)
5. Runs `pi auth check --provider <name> --json` to verify

---

## 🔀 How the merge works

Updating an existing profile does **not** rewrite it. Fields the script does not
manage stay as you left them:

| Field | What happens |
|---|---|
| `apiKey` | if you leave the prompt empty, it **stays**. It used to be wiped, and that was the most common case |
| `promptCache`, `headers`, `compat`, `cost` | your customizations are **preserved** |
| Extra models | merged by `id`: a new one is appended, an existing `id` is updated **in place**, without reordering |
| Neighbouring providers | **not** touched |

The only things that change are what you just answered to prompts 7 and 8
(`contextWindow`, `maxTokens`) and the `apiKey` **if and only if** you typed it.

```json
{
  "baseUrl": "https://api.server.example",
  "api": "anthropic-messages",
  "apiKey": "$MLR_API_KEY",
  "models": [
    {
      "id": "MLR-3",
      "name": "MLR-3",
      "reasoning": true,
      "input": ["text"],
      "contextWindow": 512000,
      "maxTokens": 32768,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
    }
  ]
}
```

### Customizing after creation

Once the profile exists you can edit `models.json` to add a real `cost` (for
per-request cost calculation), `promptCache.short`/`long` (cache hit/miss
tracking), `compat.*` (provider-specific flags) and custom `headers` (e.g. for a
tenant ID or a routing header).

pi re-reads `models.json` on every `/model` — **no restart needed**.

> These fields **survive** a re-run of the script on the same profile: the merge
> is field by field and preserves them.

---

## 🤖 Non-interactive use

Without `add` the scripts ask the 8 questions. With `add` (or with the flags
alone, which imply it) they ask nothing and are suitable for **provisioning**
and scripts.

```bash
pi-conf.sh add \
  --endpoint https://api.server.example \
  --api anthropic \
  --model MLR-3 \
  --key-env MLR_API_KEY \
  --yes
```

```powershell
.\pi-conf.ps1 add -Endpoint https://api.server.example -Api anthropic `
  -Model MLR-3 -KeyEnv MLR_API_KEY
```

| Flag | Default | Notes |
|---|---|---|
| `--endpoint <url>` | — | required, unless `--from-file` |
| `--api <name>` | `anthropic` | friendly name, see list above |
| `--model <id>` | — | required, unless `--from-file` |
| `--profile <name>` | sanitized model id | |
| `--key <value>` | — | writes the key **in clear**, discouraged |
| `--key-env <NAME>` | — | writes `"apiKey": "$NAME"`, **use this** |
| `--reasoning` / `--no-reasoning` | enabled | |
| `--context <n>` | `512000` | |
| `--max-tokens <n>` | `32768` | |
| `--from-file <json>` | — | fills in the missing fields |
| `--config <path>` | pi config | where to write |
| `--dry-run` | — | preview, does not write |
| `--print-config` | — | resulting JSON on stdout |
| `--yes` | — | does not ask for confirmation |

> [!TIP]
> **`--key-env` is the flag that matters.** pi resolves `"$MLR_API_KEY"` from the
> environment on every request, so the credential **never lands in clear** in
> `models.json`. If the variable is not set when pi starts, the provider will
> show as unauthenticated.

### Interactive use

```bash
# from the repo directory
chmod +x pi-conf.sh
./pi-conf.sh
./pi-conf.sh --help
```

```powershell
# from PowerShell
.\pi-conf.ps1
.\pi-conf.ps1 -Help
```

<details>
<summary><b>If PowerShell blocks the script (<i>execution policy</i>)</b></summary>

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

or, for that single run:

```powershell
powershell -ExecutionPolicy Bypass -File .\pi-conf.ps1
```

</details>

### Environment variables

| Variable | Effect |
|---|---|
| `PI_CONF_FILE` | Path of the `models.json` to write |
| `PI_CODING_AGENT_DIR` | pi directory from which to derive the path |
| `PI_BIN` | Path of the `pi` binary. **Difference between the two scripts:** in PowerShell it takes precedence over `pi` in PATH; in bash it is used **only** if `pi` is not already in PATH, otherwise it is silently ignored |

> [!NOTE]
> With `PI_CONF_FILE` or `PI_CODING_AGENT_DIR` set, the final check is **not
> reliable**: `pi auth check` reads pi's configuration, not the file the script
> has just written.

---

## 📦 Dependencies

| Script | Requires |
|---|---|
| `pi-conf.sh` (bash) | `jq` (on macOS: `brew install jq`) |
| `pi-conf.ps1` (PowerShell) | nothing — native PowerShell cmdlets only |

Both obviously require `pi` installed and a writable `~/.pi/agent/`.

### 📁 Files

| File | OS | Shell |
|---|---|---|
| `pi-conf.sh` | macOS / Linux | bash 3.2+ (also bash 4/5) |
| `pi-conf.ps1` | Windows | PowerShell 5.1 (Win10/11 default) or pwsh 7+ |
| `install.sh` | macOS / Linux | POSIX sh, no dependency beyond `curl`/`wget` |
| `install.ps1` | Windows | PowerShell 5.1 or pwsh 7+ |
| `install-provider.sh` | macOS / Linux | POSIX sh, installs and configures |
| `install-provider.ps1` | Windows | PowerShell 5.1 or pwsh 7+ |
| [`docs/index.html`](https://alf-robotics.github.io/pi-configurator/) | — | self-contained support page |
| `tests/pi-conf-test.sh` | macOS / Linux | test suite |

---

## 🔒 Security

- **bash**: `models.json` is written with mode **`0600`** (owner read/write).
- **PowerShell**: NTFS applies per-user ACLs automatically; by default the file
  is accessible only to your Windows account.
- In both cases, **do not share `models.json`**: it contains API keys in clear.
- The **terminal preview** masks the `apiKey`: it shows `••••••••` plus the last
  4 digits. The clear value only ever reaches the file.

---

## 🧪 Tests

```bash
bash tests/pi-conf-test.sh
```

**117 assertions in 14 sections.** They cover non-destructive merge, backup,
preview masking, file permissions, non-interactive mode, `sanitize_name`, the two
installers, and a guard that verifies the suite never touched the real
`models.json`.

`pi-conf.sh`, `install.sh` and `install-provider.sh` are covered by **executing**
them; the three PowerShell files are only covered by static checks, because
`pwsh` is not needed to run the suite.

The suite has been verified **by sabotage**: disabling the installer's SHA256
verification, the dash trimming in `sanitize_name`, the writing of `--key-env` as
an env reference, the early check on `--model` or the `has("apiKey")` guard, the
suite **fails** in all five cases.

---

## 🚧 Known limits

- **None of the PowerShell files has ever been executed.** `pi-conf.ps1`,
  `install.ps1` and `install-provider.ps1` have static coverage only (balanced
  braces, presence of markers, consistency of defaults between the two
  implementations). The logic must be verified on Windows.
- **The installers have never been tested automatically against GitHub.** The
  tests exercise them from a local checkout, which is a different path from a
  network download. The `curl … | sh` line was run by hand and worked, downloading
  from the tag and passing the SHA256 check, but it is not repeatable.
- **The final `pi-conf` check is reliable only on the default config.** With
  `PI_CONF_FILE` or `PI_CODING_AGENT_DIR` set, `pi auth check` reads pi's
  configuration and not the file just written.
- **The two pi-conf implementations are not identical.** `PI_BIN` takes
  precedence in PowerShell, in bash it is used only if `pi` is not in PATH.
  Unreadable-file handling is now aligned (both abort without writing), but the
  rest is not covered by tests.
- **No backup when the file does not exist**: on the first save there is nothing
  to preserve. And the backup is overwritten on every run.
- **`cost` stays at zero** until you edit it by hand, and `input: ["text"]` is
  fixed: no multimodal input.
- **No CI**: the suite passes only if someone runs it.

---

<div align="center">

**MIT** · [EULA v1.1](EULA.en.md) ([IT](EULA.md)) · release [`v0.3.1`](https://github.com/ALF-Robotics/pi-configurator/releases) · [🌐 support page](https://alf-robotics.github.io/pi-configurator/)

<sub>🇮🇹 <a href="README.md">Italiano</a> · 🇬🇧 <b>English</b></sub>

</div>
