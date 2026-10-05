# pi-configurator

<div align="center">
  <b>Script interattivi per creare e aggiornare profili provider di <a href="https://pi.dev/">pi-code</a></b>
  <br>
  <sub>bash + PowerShell · merge non distruttivo · una riga di comando per il provisioning</sub>
</div>

<div align="center">

[![license](https://img.shields.io/github/license/ALF-Robotics/pi-configurator?style=flat&label=license)](LICENSE)
[![tag](https://img.shields.io/github/v/tag/ALF-Robotics/pi-configurator?style=flat&label=release)](https://github.com/ALF-Robotics/pi-configurator/releases)
[![last-commit](https://img.shields.io/github/last-commit/ALF-Robotics/pi-configurator?style=flat)](https://github.com/ALF-Robotics/pi-configurator/commits/main)
[![stars](https://img.shields.io/github/stars/ALF-Robotics/pi-configurator?style=flat&label=stars)](https://github.com/ALF-Robotics/pi-configurator/stargazers)
[![EULA](https://img.shields.io/badge/EULA-v1.1-informational)](EULA.md)
[![EULA-en](https://img.shields.io/badge/EULA-EN-informational)](EULA.en.md)
[![type](https://img.shields.io/badge/type-utility-blueviolet)](#-cosa-fa)
[![target](https://img.shields.io/badge/target-pi%20%28pi--coding--agent%29-ff69d4)](https://pi.dev/)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#-file)
[![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)](pi-conf.sh)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-012456)](pi-conf.ps1)
[![dep](https://img.shields.io/badge/dep-jq-c0c0c0)](#-dipendenze)

</div>

<p align="center">
  🇮🇹 <b>Italiano</b> &nbsp;·&nbsp; 🇬🇧 <a href="README.en.md"><b>English</b></a>
</p>

---

> [!IMPORTANT]
> Il codice è sotto licenza [MIT](LICENSE). L'uso dello script come strumento
> operativo — incluse le credenziali che vi vengono affidate — è disciplinato
> dalle condizioni dell'[EULA](EULA.md) v1.1, che **coesiste** con la MIT e non la
> sostituisce. Il testo italiano fa prevalere in caso di divergenza; ne esiste una
> [traduzione inglese](EULA.en.md) priva di autonoma efficacia giuridica.

## 📋 Indice

- [Installazione rapida](#-installazione-rapida)
- [Cosa fa](#-cosa-fa)
- [Come funziona il merge](#-come-funziona-il-merge)
- [Uso non interattivo](#-uso-non-interattivo)
- [Dipendenze](#-dipendenze)
- [Sicurezza](#-sicurezza)
- [Test](#-test)
- [Limiti noti](#-limiti-noti)

---

## 🚀 Installazione rapida

**Solo il tool**, se poi lo usi a mano o in interattivo:

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.ps1 | iex
```

**Tool e provider insieme**, per il provisioning:

```bash
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.sh \
  | sh -s -- \
      --endpoint https://api.server.example \
      --api anthropic \
      --model MLR-3 \
      --key-env MLR_API_KEY
```

Installa in `~/.local/bin` (Windows: `%USERPROFILE%\.pi-configurator`) e verifica
ogni file scaricato con lo **SHA256** prima di scrivere: se l'hash non corrisponde
l'installazione si ferma senza toccare nulla.

> [!TIP]
> **Pinna la versione.** `main` può cambiare in qualsiasi momento, un tag no:
> `curl -fsSL .../main/install.sh | sh -s -- --ref v0.3.0`

<details>
<summary><b>Installer per Windows (PowerShell), opzioni complete</b></summary>

```powershell
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.ps1 | iex -args @(
    '-Endpoint','https://api.server.example',
    '-Api','anthropic',
    '-Model','MLR-3',
    '-KeyEnv','MLR_API_KEY'
)
```

</details>

### Opzioni degli installer

| Installer | Ruolo | Flag del provider |
|---|---|---|
| `install.sh` / `install.ps1` | scarica e verifica il tool | dopo `--` |
| `install-provider.sh` / `.ps1` | installa **e** configura | di primo livello, senza `--` |

Entrambi accettano `--ref`, `--prefix`, `--dry-run`, `--no-verify`.
`install-provider` accetta in più i flag del provider (`--endpoint`, `--model`,
`--key-env`, …) e **rifiuta** un `--endpoint` o `--model` mancante *prima* di
installare qualsiasi cosa.

`install-provider` verifica anche l'hash di `install.sh` prima di eseguirlo:
è codice che sta per girare, non un semplice file da mettere in `/usr/local/bin`.

---

## 🎯 Cosa fa

Gli script scrivono in `~/.pi/agent/models.json`
(Windows: `%USERPROFILE%\.pi\agent\models.json`) facendo **merge**, non
sovrascrittura: aggiungono il provider senza toccare gli altri, e aggiornano un
profilo esistente **campo per campo** conservando `apiKey`, `promptCache`,
`headers`, `compat`, `cost` e i modelli aggiuntivi.
Prima di ogni scrittura viene creato un backup in `models.json.bak`.

### Le 8 domande

| # | Domanda | Default |
|---|---|---|
| 1 | **Endpoint URL** (es. `https://api.server.example`) | — |
| 2 | **Standard API** — friendly name mappato in automatico | `anthropic` |
| 3 | **Model ID** (es. `MLR-3`, `claude-sonnet-4-5`) | — |
| 4 | **Nome del profilo** (provider name in pi) | model id sanitizzato |
| 5 | **API key** — opzionale; vuoto = configura dopo con `/login` | — |
| 6 | **Reasoning esteso?** | `y` |
| 7 | **Context window** | `512000` |
| 8 | **Max output tokens** | `32768` |

<details>
<summary><b>Standard API: come viene tradotto il friendly name</b></summary>

| Scrivi | Ottieni |
|---|---|
| `anthropic` | `anthropic-messages` |
| `openai` | `openai-completions` |
| `responses` | `openai-responses` |
| `google` | `google-generative-ai` |
| `mistral`, `bedrock`, `vertex`, `codex`, `azure` | il nome corrispondente |
| `<altro>` | passato a pi **tal quale** |

</details>

La API key viene mostrata come `*` durante il typing o il paste, per dare
feedback visivo, e il backspace funziona normalmente.

> [!WARNING]
> **`maxTokens` include i token di ragionamento.** Con `anthropic-messages` il
> tetto vale per il completamento **intero**: con il Reasoning attivo i `32768`
> default sono il budget di ragionamento **più** risposta. Ecco perché il default
> è `32768` e non `16384`: quella è una cifra adatta a un modello senza
> ragionamento, e con il Reasoning a `y` (che è il default) ti taglierebbe le
> risposte lunghe **in silenzio, senza errore**.

### Flusso finale

1. Mostra anteprima JSON del provider
2. Se il nome profilo esiste già → chiede conferma di sovrascrittura
3. Chiede conferma finale
4. Merge con `jq` (bash) o `ConvertFrom-Json`/`ConvertTo-Json` (PowerShell)
5. Esegue `pi auth check --provider <nome> --json` per verifica

---

## 🔀 Come funziona il merge

Aggiornare un profilo esistente **non** lo riscrive. I campi che lo script non
gestisce restano quelli che avevi:

| Campo | Cosa succede |
|---|---|
| `apiKey` | se lasci il prompt vuoto, **resta**. Prima veniva cancellata, ed era il caso più comune |
| `promptCache`, `headers`, `compat`, `cost` | personalizzazioni **conservate** |
| Modelli aggiuntivi | uniti per `id`: uno nuovo in coda, un `id` già presente aggiornato **nella sua posizione**, senza riordinare |
| Provider vicini | **non** vengono toccati |

L'unica cosa che cambia è ciò che hai appena risposto ai prompt 7 e 8
(`contextWindow`, `maxTokens`) e l'`apiKey` **se e solo se** la digiti.

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

### Personalizzazione dopo la creazione

Dopo aver creato il profilo puoi editare `models.json` per aggiungere `cost`
reale (calcolo costo per richiesta), `promptCache.short`/`long` (tracking
cache hit/miss), `compat.*` (flag specifici del provider) e `headers` custom
(es. per tenant ID, routing header).

pi rilegge `models.json` ad ogni `/model` — **nessun restart necessario**.

> Questi campi **sopravvivono** a un re-run dello script sullo stesso profilo:
> il merge è campo per campo e li conserva.

---

## 🤖 Uso non interattivo

Senza `add` gli script fanno le 8 domande. Con `add` (o con i flag da soli, che
lo implicano) non fanno domande e sono adatti a **provisioning** e script.

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

| Flag | Default | Note |
|---|---|---|
| `--endpoint <url>` | — | obbligatorio, salvo `--from-file` |
| `--api <nome>` | `anthropic` | friendly name, vedi elenco sopra |
| `--model <id>` | — | obbligatorio, salvo `--from-file` |
| `--profile <nome>` | model id sanitizzato | |
| `--key <valore>` | — | scrive la chiave **in chiaro**, sconsigliato |
| `--key-env <NOME>` | — | scrive `"apiKey": "$NOME"`, **usalo questo** |
| `--reasoning` / `--no-reasoning` | attivo | |
| `--context <n>` | `512000` | |
| `--max-tokens <n>` | `32768` | |
| `--from-file <json>` | — | riempie i campi mancanti |
| `--config <path>` | config di pi | dove scrivere |
| `--dry-run` | — | anteprima, non scrive |
| `--print-config` | — | JSON risultante su stdout |
| `--yes` | — | non chiede conferma |

> [!TIP]
> **`--key-env` è l'opzione che conta.** Pi risolve `"$MLR_API_KEY"` dall'ambiente
> a ogni richiesta, quindi la credenziale **non finisce mai in chiaro** in
> `models.json`. Se la variabile non è impostata quando parte pi, il provider
> risulta non autenticato.

### Uso interattivo

```bash
# dalla cartella del repo
chmod +x pi-conf.sh
./pi-conf.sh
./pi-conf.sh --help
```

```powershell
# da PowerShell
.\pi-conf.ps1
.\pi-conf.ps1 -Help
```

<details>
<summary><b>Se PowerShell blocca lo script (<i>execution policy</i>)</b></summary>

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

oppure, per la singola esecuzione:

```powershell
powershell -ExecutionPolicy Bypass -File .\pi-conf.ps1
```

</details>

### Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `PI_CONF_FILE` | Path del `models.json` da scrivere |
| `PI_CODING_AGENT_DIR` | Directory di pi da cui derivare il path |
| `PI_BIN` | Percorso del binario `pi`. **Differenza tra i due script:** in PowerShell ha precedenza su `pi` in PATH; in bash viene usato **solo** se `pi` non è già in PATH, altrimenti è ignorato in silenzio |

> [!NOTE]
> Con `PI_CONF_FILE` o `PI_CODING_AGENT_DIR` impostati la verifica finale **non
> è attendibile**: `pi auth check` legge la configurazione di pi, non il file che
> lo script ha appena scritto.

---

## 📦 Dipendenze

| Script | Richiede |
|---|---|
| `pi-conf.sh` (bash) | `jq` (su macOS: `brew install jq`) |
| `pi-conf.ps1` (PowerShell) | niente — usa solo cmdlets nativi PowerShell |

Entrambi richiedono ovviamente `pi` installato e un `~/.pi/agent/` scrivibile.

### 📁 File

| File | OS | Shell |
|---|---|---|
| `pi-conf.sh` | macOS / Linux | bash 3.2+ (anche bash 4/5) |
| `pi-conf.ps1` | Windows | PowerShell 5.1 (default Win10/11) o pwsh 7+ |
| `install.sh` | macOS / Linux | POSIX sh, senza dipendenze oltre `curl`/`wget` |
| `install.ps1` | Windows | PowerShell 5.1 o pwsh 7+ |
| `install-provider.sh` | macOS / Linux | POSIX sh, installa e configura |
| `install-provider.ps1` | Windows | PowerShell 5.1 o pwsh 7+ |
| [`docs/index.html`](https://alf-robotics.github.io/pi-configurator/) | — | pagina di supporto, autoportante |
| `tests/pi-conf-test.sh` | macOS / Linux | suite di test |

---

## 🔒 Sicurezza

- **bash**: `models.json` viene scritto con mode **`0600`** (owner read/write).
- **PowerShell**: NTFS applica ACL per-user automaticamente; il file è
  accessibile solo al tuo account Windows per default.
- In entrambi i casi, **non condividere `models.json`**: contiene le API key
  in chiaro.
- L'**anteprima a terminale** maschera la `apiKey`: mostra `••••••••` e le
  ultime 4 cifre. Il valore in chiaro finisce solo nel file.

---

## 🧪 Test

```bash
bash tests/pi-conf-test.sh
```

**117 asserzioni in 14 sezioni.** Coprono merge non distruttivo, backup,
mascheramento in anteprima, permessi del file, modalità non interattiva,
`sanitize_name`, i due installer e una guardia che verifica che la suite non
abbia mai toccato il `models.json` reale.

`pi-conf.sh`, `install.sh` e `install-provider.sh` sono coperti **eseguendoli**;
i tre file PowerShell sono presi in carico solo da controlli statici, perché
`pwsh` non è necessario per eseguire la suite.

La suite è stata verificata **per sabotaggio**: disattivando la verifica SHA256
dell'installer, il ritaglio del trattino in `sanitize_name`, la scrittura di
`--key-env` come riferimento env, il controllo anticipato su `--model` o la
guardia `has("apiKey")`, la suite **fallisce** in tutti e cinque i casi.

---

## 🚧 Limiti noti

- **Nessuno dei file PowerShell è mai stato eseguito.** `pi-conf.ps1`,
  `install.ps1` e `install-provider.ps1` hanno copertura solo statica (grafi
  bilanciati, presenza dei marker, coerenza dei default fra le due
  implementazioni). La logica va verificata su Windows.
- **Gli installer non sono mai stati provati in un test automatico contro
  GitHub.** I test li esercitano da checkout locale, che è un percorso diverso
  dal download via rete. La riga `curl … | sh` è stata eseguita a mano e ha
  funzionato, scaricando dal tag e passando la verifica SHA256, ma non è
  ripetibile.
- **La verifica finale di `pi-conf` è attendibile solo sul config di default.**
  Con `PI_CONF_FILE` o `PI_CODING_AGENT_DIR` impostati, `pi auth check` legge la
  configurazione di pi e non il file appena scritto.
- **Le due implementazioni di pi-conf non sono identiche.** `PI_BIN` ha la
  precedenza in PowerShell, in bash viene usato solo se `pi` non è in PATH. La
  gestione del file non leggibile ora è allineata (entrambe abortiscono senza
  scrivere), ma il resto non è coperto da test.
- **Nessun backup quando il file non esiste**: sul primo salvataggio non c'è
  nulla da conservare. E il backup viene sovrascritto a ogni esecuzione.
- **`cost` resta a zero** finché non lo editi a mano, e `input: ["text"]` è
  fisso: niente input multimodale.
- **Nessuna CI**: la suite passa solo se qualcuno la lancia.

---

<div align="center">

**MIT** · [EULA v1.1](EULA.md) ([EN](EULA.en.md)) · rilascio [`v0.3.1`](https://github.com/ALF-Robotics/pi-configurator/releases)

<sub>🇮🇹 <b>Italiano</b> · 🇬🇧 <a href="README.en.md">English</a></sub>

</div>
