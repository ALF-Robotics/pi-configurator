# pi-configurator

Script interattivi per creare/aggiornare **profili provider custom** di
[pi-code](https://pi.dev/) (CLI: `@mariozechner/pi-coding-agent`).

Scrivono in `~/.pi/agent/models.json` (Windows: `%USERPROFILE%\.pi\agent\models.json`),
facendo **merge** con i provider già presenti (no overwrite).

## File

| File | OS | Shell |
|---|---|---|
| `pi-conf.sh` | macOS / Linux | bash 3.2+ (anche bash 4/5) |
| `pi-conf.ps1` | Windows | PowerShell 5.1 (default Win10/11) o pwsh 7+ |

## Cosa fa

Entrambi gli script sono interattivi e chiedono 8 cose:

1. **Endpoint URL** (es. `https://api.server.example`)
2. **Standard API** — friendly name mappato automaticamente:
   - `anthropic` → `anthropic-messages`
   - `openai` → `openai-completions`
   - `responses` → `openai-responses`
   - `google` → `google-generative-ai`
   - `mistral`, `bedrock`, `vertex`, `codex`, `azure`
   - `<raw>` → nome API pi passato tal quale
3. **Model ID** (es. `MLR-3`, `claude-sonnet-4-5`)
4. **Nome del profilo** (provider name in pi; default = model-id sanitizzato)
5. **API key** — opzionale; vuoto = configura dopo con `/login`
   - Mostrata come `*` durante typing/paste per dare feedback visivo
   - Backspace funziona
6. **Reasoning esteso?** (y/N)
7. **Context window** (default 200000)
8. **Max output tokens** (default 16384)

## Flusso finale (comune a entrambi)

1. Mostra anteprima JSON del provider
2. Se il nome profilo esiste già → chiede conferma di sovrascrittura
3. Chiede conferma finale
4. Merge con `jq` (bash) o `ConvertFrom-Json`/`ConvertTo-Json` (PowerShell) nel file `models.json`
5. Esegue `pi auth check --provider <nome> --json` per verifica

## Uso

### macOS / Linux

```bash
chmod +x pi-conf.sh
pi-conf.sh
pi-conf.sh --help
```

### Windows (PowerShell)

```powershell
# Da PowerShell, nella cartella pi-configurator
.\pi-conf.ps1
.\pi-conf.ps1 -Help
```

Se PowerShell blocca lo script con errore di *execution policy*:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

…oppure lancialo bypassando per la singola esecuzione:

```powershell
powershell -ExecutionPolicy Bypass -File .\pi-conf.ps1
```

## Dipendenze

| Script | Richiede |
|---|---|
| `pi-conf.sh` (bash) | `jq` (su macOS: `brew install jq`) |
| `pi-conf.ps1` (PowerShell) | niente — usa solo cmdlets nativi PowerShell |

Entrambi richiedono ovviamente `pi` installato e un `~/.pi/agent/` scrivibile.

## Note di sicurezza

- **bash**: il file `models.json` viene scritto con mode `0600` (owner read/write).
- **PowerShell**: NTFS applica ACL per-user automaticamente; il file è
  accessibile solo al tuo account Windows per default.
- In entrambi i casi, **non condividere `models.json`**: contiene le API key
  in chiaro.

## Esempio di output (anteprima JSON)

```json
{
  "baseUrl": "https://api.server.example",
  "api": "anthropic-messages",
  "apiKey": "<API_KEY>",
  "models": [
    {
      "id": "MLR-3",
      "name": "MLR-3",
      "reasoning": true,
      "input": ["text"],
      "contextWindow": 200000,
      "maxTokens": 16384,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
    }
  ]
}
```

## Personalizzazione post-creazione

Dopo aver creato il profilo puoi editare `models.json` per aggiungere:

- `cost` reale (per il calcolo cost per richiesta)
- `promptCache.short` / `long` (per il tracking cache hit/miss)
- `compat.*` (flag specifici per il tuo provider)
- `headers` custom (es. per tenant ID, routing header)

pi rilegge `models.json` ad ogni `/model` — nessun restart necessario.
