# pi-configurator

<!--
  Badge statici con valori verificati: i badge dinamici `github/...` di
  shields.io NON funzionano su questo repo perché è privato — restituiscono
  200 ma con immagine "repo not found".
  Volutamente assenti:
  - star      : non esiste un badge stars che legga un repo privato
  - versione  : il repo non ha ancora tag, quindi non c'è una versione vera
  - test      : la suite gira solo se qualcuno la lancia, non in CI
-->
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![EULA](https://img.shields.io/badge/EULA-v1.1-informational)](EULA.md)
[![type](https://img.shields.io/badge/type-utility-blueviolet)](#cosa-fa)
[![target](https://img.shields.io/badge/target-pi%20%28pi--coding--agent%29-ff69d4)](https://pi.dev/)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#file)
[![languages](https://img.shields.io/badge/languages-Shell%20%2B%20PowerShell-89e051)](#file)
[![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)](pi-conf.sh)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-012456)](pi-conf.ps1)
[![dep](https://img.shields.io/badge/dep-jq-c0c0c0)](#dipendenze)

Script interattivi per creare/aggiornare **profili provider custom** di
[pi-code](https://pi.dev/) (CLI: `@earendil-works/pi-coding-agent`).

> Il codice è sotto licenza [MIT](LICENSE). L'uso dello script come strumento
> operativo — incluse le credenziali che vi vengono affidate — è disciplinato
> dalle condizioni dell'[EULA](EULA.md), che coesiste con la MIT e non la
> sostituisce.

Scrivono in `~/.pi/agent/models.json` (Windows: `%USERPROFILE%\.pi\agent\models.json`)
facendo **merge**, non sovrascrittura: aggiungono il provider senza toccare
gli altri, e aggiornano un profilo esistente campo per campo conservando
`apiKey`, `promptCache`, `headers`, `compat`, `cost` e i modelli aggiuntivi.
Prima di ogni scrittura viene creato un backup in `models.json.bak`.

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
- L'**anteprima a terminale** maschera la `apiKey`: mostra `••••••••` e le
  ultime 4 cifre. Il valore in chiaro finisce solo nel file.

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

> Questi campi **sopravvivono** a un re-run dello script sullo stesso profilo:
> il merge è campo per campo e li conserva. Vedi
> [Come funziona il merge](#come-funziona-il-merge).

## Come funziona il merge

Aggiornare un profilo esistente **non** lo riscrive. I campi che lo script non
gestisce restano quelli che avevi:

- **`apiKey`** — se lasci il prompt vuoto, la chiave già salvata **resta**.
  Prima veniva cancellata, ed era il caso più comune.
- **`promptCache`, `headers`, `compat`, `cost` personalizzati** — conservati.
- **Modelli aggiuntivi** — uniti per `id`. Un modello nuovo viene aggiunto in
  coda; un `id` già presente viene aggiornato nella sua posizione, senza
  riordinare l'elenco.
- **Provider vicini** — non vengono toccati.

L'unica cosa che cambia è ciò che hai appena risposto ai prompt 7 e 8
(`contextWindow`, `maxTokens`) e l'`apiKey` **se e solo se** la digiti.

Prima di scrivere, il file corrente viene copiato in `models.json.bak`.

## Test

```bash
bash tests/pi-conf-test.sh
```

38 asserzioni che coprono il merge, il backup, il mascheramento in anteprima e
i permessi del file. Copre `pi-conf.sh` **eseguendolo**; `pi-conf.ps1` è
preso in carico solo da controlli statici, perché `pwsh` non è necessario per
eseguire la suite.

## Limiti noti

- **La verifica finale è attendibile solo sul config di default.** Con
  `PI_CONF_FILE` o `PI_CODING_AGENT_DIR` impostati, `pi auth check` legge la
  configurazione di pi e non il file appena scritto.
- **Le due implementazioni non sono identiche.** `PI_BIN` ha la precedenza in
  PowerShell, in bash viene usato solo se `pi` non è in PATH. La gestione del
  file non leggibile ora è allineata (entrambe abortiscono senza scrivere),
  ma il resto non è coperto da test.
- **`pi-conf.ps1` non è eseguito dai test.** Serve una verifica su Windows.
- **Nessun backup quando il file non esiste**: sul primo salvataggio non c'è
  nulla da conservare.
- **`cost` resta a zero** finché non lo editi a mano.
