# pi-configurator

Script interattivi per creare/aggiornare **profili provider custom** di
[pi-code](https://pi.dev/) (CLI: `@mariozechner/pi-coding-agent`).

Scrivono in `~/.pi/agent/models.json` (Windows: `%USERPROFILE%\.pi\agent\models.json`),
aggiungendo il provider **senza toccare gli altri**. Attenzione però: se il
**nome del profilo** esiste già, quel provider viene riscritto per intero — vedi
[Limiti noti](#limiti-noti).

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
6. **Reasoning esteso?** (y/N, default `y`)
7. **Context window** (default 512000)
8. **Max output tokens** (default 32768)

> **`maxTokens` include i token di ragionamento.** Con `anthropic-messages` il
> tetto vale per il completamento intero: con il Reasoning attivo i 32768
> default sono il budget di ragionamento **più** risposta. Ecco perché il
> default è 32768 e non 16384: quella è una cifra adatta a un modello senza
> ragionamento, e con il Reasoning a `y` (che è il default) ti taglierebbe le
> risposte lunghe in silenzio, senza errore.

## Flusso finale (comune a entrambi)

1. Mostra anteprima JSON del provider
2. Se il nome profilo esiste già → chiede conferma di sovrascrittura
3. Chiede conferma finale
4. Merge con `jq` (bash) o `ConvertFrom-Json`/`ConvertTo-Json` (PowerShell) nel file `models.json`
5. Esegue `pi auth check --provider <nome> --json` per verifica

## Uso

### macOS / Linux

```bash
# dalla cartella del repo
chmod +x pi-conf.sh
./pi-conf.sh
./pi-conf.sh --help
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

### Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `PI_CONF_FILE` | Path del `models.json` da scrivere |
| `PI_CODING_AGENT_DIR` | Directory di pi da cui derivare il path |
| `PI_BIN` | Percorso del binario `pi`. **Differenza tra i due script:** in PowerShell ha la precedenza su `pi` in PATH; in bash viene usato **solo** se `pi` non è già in PATH, altrimenti è ignorato in silenzio |

Con `PI_CONF_FILE` o `PI_CODING_AGENT_DIR` impostati, la verifica finale non
è attendibile: `pi auth check` legge la configurazione di pi, non il file che
lo script ha appena scritto.

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
- L'**anteprima a terminale** riprende la `apiKey` in chiaro, anche se la
  mascheri durante la digitazione: resta nello scrollback.

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
      "contextWindow": 512000,
      "maxTokens": 32768,
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

> **Attenzione:** tutti questi campi vengono persi se rilanci lo script sullo
> stesso nome profilo. Vedi sotto.

## Limiti noti

Due difetti aperti, entrambi tracciati su GitHub:

- **Il re-run sullo stesso profilo riscrive il provider per intero**
  ([#1](https://github.com/ALF-Robotics/pi-configurator/issues/1)). Non è un
  merge campo per campo: modelli aggiuntivi, `apiKey`, `promptCache`,
  `headers` e `cost` personalizzati spariscono. Nel flusso più comune — API
  key lasciata vuota perché "la configuri dopo" — è proprio la `apiKey` che
  viene cancellata. **Fai una copia di `models.json` prima di rilanciare.**
- **L'anteprima stampa la API key in chiaro**
  ([#2](https://github.com/ALF-Robotics/pi-configurator/issues/2)).

Nessun backup automatico: lo script scrive con `mv`, quindi un merge andato
storto non è recuperabile dal file precedente.
