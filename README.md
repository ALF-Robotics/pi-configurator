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
[![EULA](https://img.shields.io/badge/EULA-v1.3-informational)](EULA.md)
[![EULA-en](https://img.shields.io/badge/EULA-EN-informational)](EULA.en.md)
[![type](https://img.shields.io/badge/type-utility-blueviolet)](#-cosa-fa)
[![target](https://img.shields.io/badge/target-pi%20%28pi--coding--agent%29-ff69d4)](https://pi.dev/)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#-file)
[![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)](pi-conf.sh)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-012456)](pi-conf.ps1)
[![dep](https://img.shields.io/badge/dep-jq-c0c0c0)](#-dipendenze)

</div>

<p align="center">
  <a href="https://alf-robotics.github.io/pi-configurator/"><b>🌐 Pagina di supporto</b></a>
  &nbsp;·&nbsp;
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

- [⚡ In una riga sola](#-in-una-riga-sola) — esegui lo script dal web, senza scaricare nulla
- [Let your AI set it up](#-let-your-ai-set-it-up) — se preferisci che lo faccia un assistente
- [Scarica ed esegui](#-scarica-ed-esegui) — il percorso manuale, con il file in locale
- [Cosa fa](#-cosa-fa) — le 9 domande, una per una
- [Come funziona il merge](#-come-funziona-il-merge)
- [Uso non interattivo](#-uso-non-interattivo) — per provisioning e script
- [Dipendenze](#-dipendenze)
- [Sicurezza](#-sicurezza)
- [Test](#-test)
- [Limiti noti](#-limiti-noti)

---

## ⚡ In una riga sola

Il modo più rapido: **nessun file da scaricare, nessun clone**. Lo script
viene eseguito direttamente dal web, sul posto.

### macOS / Linux

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.sh)"
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.ps1 | iex
```

`irm` è l'alias di `Invoke-WebRequest`, `iex` quello di `Invoke-Expression`.
Per esteso:

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.ps1 | Invoke-Expression
```

> [!NOTE]
> **In PowerShell il pipe funziona anche in interattivo**, al contrario di bash:
> lo stdin non viene toccato, quindi le prompt leggono le tue risposte.
> `-UseBasicParsing` serve a Windows PowerShell 5.1 (su PowerShell 7 è
> ridondante, ma innocuo).

### Configurazione remota, senza domande

Per il provisioning — un server, un container, un'installazione non presidiata —
gli stessi script girano in non interattivo.

```bash
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.sh \
  | bash -s -- add \
      --endpoint https://api.server.example \
      --api anthropic \
      --model MLR-3 \
      --key-env MLR_API_KEY \
      --yes
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.ps1).Content)) add `
    -Endpoint https://api.server.example -Api anthropic -Model MLR-3 -KeyEnv MLR_API_KEY -Yes
```

> [!WARNING]
> **`curl … | bash` in interattivo non funziona.** Con il pipe lo stdin contiene
> il testo dello script, quindi le prompt leggerebbero lo script invece delle
> tue risposte: la configurazione non viene scritta.
>
> Per questo la forma interattiva usa `bash -c "…"`: lo script arriva come
> stringa di comando e lo stdin resta il terminale. Nella forma non interattiva
> il pipe è invece la scelta giusta, perché `add` non legge mai stdin.

> [!TIP]
> **Pinna la versione.** Gli esempi qui usano il tag `v0.4.1`. Sostituiscilo
> con `main` solo se segui deliberatamente la versione di sviluppo: `main` può
> cambiare in qualsiasi momento.

### Cosa succede

Lo script ti chiede 9 cose — endpoint, standard API, model id, nome del profilo,
API key, reasoning, context window, max output tokens, multimodale — e poi:

1. mostra l'anteprima JSON, con la `apiKey` **mascherata**
2. se il profilo esiste già, chiede conferma di sovrascrittura
3. chiede la conferma finale
4. fa il merge con `jq` (bash) o `ConvertFrom-Json`/`ConvertTo-Json`
   (PowerShell) e scrive `~/.pi/agent/models.json` con mode `600`, dopo averne
   creato il backup in `models.json.bak`
5. esegue `pi auth check --provider <nome> --json` per verificare

Le 9 domande una per una sono in [Cosa fa](#-cosa-fa).

> [!TIP]
> **La API key è opzionale.** Se la lasci vuota il profilo viene creato senza
> credenziale e la configuri dopo con `/login <nome>`, oppure con una variabile
> d'ambiente. In ogni caso l'anteprima mostra la chiave **mascherata**
> (`••••••••` + ultime 4 cifre): il valore in chiaro finisce solo nel file.

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


---

## 📥 Scarica ed esegui

Se preferisci avere il file in locale — per ripeterlo, per ispezionarlo o per
metterlo nel `PATH`:

### Scarica

```bash
# macOS / Linux
curl -fsSL -o pi-conf.sh https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.sh
```

```powershell
# Windows
irm -OutFile pi-conf.ps1 https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/v0.4.1/pi-conf.ps1
```

> [!TIP]
> **Pinna la versione.** `main` può cambiare in qualsiasi momento, un tag no.
> Sostituisci `v0.4.1` con il tag che ti serve.

### Lancia

```bash
chmod +x pi-conf.sh
./pi-conf.sh
```

```powershell
.\pi-conf.ps1
```

> [!NOTE]
> **Serve `jq`** (su macOS: `brew install jq`). Su Windows non serve niente:
> `pi-conf.ps1` usa solo cmdlets nativi.

<details>
<summary><b>Altre modalità (opzionale)</b></summary>

Per installare il tool nel `PATH` invece di scaricarlo a mano:

```bash
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.ps1 | iex
```

Installa in `~/.local/bin` (Windows: `%USERPROFILE%\.pi-configurator`) e verifica
ogni file scaricato con lo **SHA256** prima di scrivere: se l'hash non corrisponde
l'installazione si ferma senza toccare nulla.

Oppure clona il repository, se vuoi anche i test:

```bash
git clone https://github.com/ALF-Robotics/pi-configurator.git
cd pi-configurator
```

</details>


---

## 🤖 Let your AI set it up

Se usi un assistente di coding (pi, Claude Code, Codex, …) puoi evitare il
copia-incolla: incolla questo prompt e l'assistente installa e configura il
provider, **verificando il download prima di eseguirlo**.

<details open>
<summary><b>Prompt pronto da usare</b></summary>

```text
Installa pi-configurator e configura il provider su questo host.

Prima di tutto leggi README.md e la sezione "Uso non interattivo": i nomi dei
flag e le procedure sono definiti li', non improvvisarli.

Procedura, senza deviazioni:

1. Scarica install-provider.sh dal TAG v0.4.1, mai da main, in una directory
   temporanea. Pinna il tag: main puo' cambiare in qualsiasi momento.
2. Verifica lo SHA256 del file scaricato confrontandolo con la voce in
   SHA256SUMS scaricata dallo STESSO ref (v0.4.1), non da main. Se non
   corrisponde, FERMATI e segnalalo. Non usare --no-verify e non eseguire
   un file non verificato.
3. Chiedimi solo cio' che non puoi dedurre: endpoint, model id, e il nome della
   variabile d'ambiente che contiene la API key. Non chiedermi la chiave in
   chiaro.
4. Esegui l'installer con:
       --ref v0.4.1
       --endpoint <endpoint>
       --api anthropic
       --model <model-id>
       --key-env <NOME_VARIABLE>
       --input text,image
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

Lo stesso prompt, in inglese, per chi preferisce dare gli ordini al
rispettivo assistente nella lingua del prompt:

<details>
<summary><b>Same prompt, in English</b></summary>

```text
Install pi-configurator and configure the provider on this host.

First read README.md and the "Non-interactive use" section: flag names and
procedures are defined there, do not improvise them.

Procedure, with no deviations:

1. Download install-provider.sh from the TAG v0.4.1, never from main, into a
   temporary directory. Pin the tag: main can change at any moment.
2. Verify the SHA256 of the downloaded file against the entry in SHA256SUMS
   fetched from the SAME ref (v0.4.1), not from main. If it does not match,
   STOP and report it. Do not use --no-verify, and never run a file you have
   not verified.
3. Ask me only for what you cannot infer: endpoint, model id, and the name of
   the environment variable holding the API key. Do not ask me for the key in
   clear.
4. Run the installer with:
       --ref v0.4.1
       --endpoint <endpoint>
       --api anthropic
       --model <model-id>
       --key-env <VAR_NAME>
       --input text,image
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

> [!NOTE]
> Il prompt è scritto per essere **incollato così com'è**. Se lo modifichi,
> conserva i tre vincoli che lo rendono sicuro: verifica SHA256 prima di
> eseguire, `--key-env` al posto di `--key`, e nessuna modifica a
> `settings.json` senza richiesta esplicita.

---

## 🎯 Cosa fa

Gli script scrivono in `~/.pi/agent/models.json`
(Windows: `%USERPROFILE%\.pi\agent\models.json`) facendo **merge**, non
sovrascrittura: aggiungono il provider senza toccare gli altri, e aggiornano un
profilo esistente **campo per campo** conservando `apiKey`, `promptCache`,
`headers`, `compat`, `cost` e i modelli aggiuntivi.
Prima di ogni scrittura viene creato un backup in `models.json.bak`.

### Le 9 domande

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
| 9 | **Accetta immagini?** | `y` → `input: ["text", "image"]` |

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

---

## 🔀 Come funziona il merge

Aggiornare un profilo esistente **non** lo riscrive. I campi che lo script non
gestisce restano quelli che avevi:

| Campo | Cosa succede |
|---|---|
| `apiKey` | se lasci il prompt vuoto, **resta**. Prima veniva cancellata, ed era il caso più comune |
| `promptCache`, `headers`, `compat`, `cost` | personalizzazioni **conservate** |
| `input` | conservato se non lo dichiari esplicitamente: un modello multimodale non viene degradato a `["text"]` |
| Modelli aggiuntivi | uniti per `id`: uno nuovo in coda, un `id` già presente aggiornato **nella sua posizione**, senza riordinare |
| Provider vicini | **non** vengono toccati |

L'unica cosa che cambia è ciò che hai appena risposto ai prompt 7, 8 e 9
(`contextWindow`, `maxTokens`, `input`) e l'`apiKey` **se e solo se** la digiti.

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
      "input": ["text", "image"],
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

Senza `add` gli script fanno le 9 domande. Con `add` (o con i flag da soli, che
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
| `--input <lista>` | `text,image` | solo `text` e `image` (l'unione di pi). **Omesso = non toccare**: conserva l'`input` già presente |
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

### Installa e configura in una riga

Se vuoi fare tutto in un colpo — installare il tool **e** configurare il
provider senza domande — c'è `install-provider.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.sh \
  | sh -s -- \
      --endpoint https://api.server.example \
      --api anthropic \
      --model MLR-3 \
      --key-env MLR_API_KEY
```

```powershell
irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.ps1 | iex -args @(
    '-Endpoint','https://api.server.example',
    '-Api','anthropic',
    '-Model','MLR-3',
    '-KeyEnv','MLR_API_KEY'
)
```

<details>
<summary><b>Opzioni degli installer</b></summary>

| Installer | Ruolo | Flag del provider |
|---|---|---|
| `install.sh` / `install.ps1` | scarica e verifica il tool | dopo `--` |
| `install-provider.sh` / `.ps1` | installa **e** configura | di primo livello, senza `--` |

Entrambi accettano `--ref`, `--prefix`, `--dry-run` e `--no-verify`.
`install-provider` accetta in più i flag del provider (`--endpoint`, `--model`,
`--key-env`, …) e **rifiuta** un `--endpoint` o `--model` mancante *prima* di
installare qualsiasi cosa.

`install-provider` verifica anche l'hash di `install.sh` prima di eseguirlo:
è codice che sta per girare, non un semplice file da mettere in `/usr/local/bin`.

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

**136 asserzioni in 15 sezioni** su `pi-conf.sh`, `install.sh` e
`install-provider.sh`: merge non distruttivo, backup, mascheratura dell'anteprima,
permessi del file, modalità non interattiva, `sanitize_name`, i due installer e
una guardia che verifica che la suite non abbia mai toccato il
`models.json` reale.

**`pi-conf.ps1` viene eseguito davvero** dalla §16, se `pwsh` è installato:
sono altre **44 asserzioni** sulle tre forme degli argomenti, sugli errori e sul
merge. Su una macchina senza PowerShell restano i controlli statici.

La suite è stata verificata **per sabotaggio**: disabilitando la verifica
SHA256 dell'installer, il trim dei trattini in `sanitize_name`, la scrittura di
`--key-env` come riferimento all'ambiente, il controllo anticipato su `--model`,
la guardia `has("apiKey")`, la preservazione di `input` nel merge, il default
di `input` forzato incondizionatamente, la validazione di `--input`, la
preservazione di `input` in PowerShell, il chiamato `Get-AddOptions -Args` in
`pi-conf.ps1`, l'`input` forzato a `["text"]` in `pi-conf.ps1` e il
`ConvertFrom-Json` su un ordered dictionary in `pi-conf.ps1`, la suite
**fallisce** in tutti e dodici i casi.

Un sabotaggio ha rivelato un test che passava per il motivo sbagliato: il
percorso interattivo scrive sempre un `input` **esplicito**, quindi non
arrivava mai al merge. Il test che ora lo copre passa da `add` senza
`--input`, ed è quello che lo sabotaggio fa scattare.

---

## 🚧 Limiti noti

- **`pi-conf.ps1` è eseguito solo dove c'è `pwsh`.** La suite PowerShell (44
  asserzioni) gira dalla §16 quando `pwsh` è installato; altrove restano i
  controlli statici. `install.ps1` e `install-provider.ps1` hanno ancora
  copertura **solo statica** (grafi bilanciati, presenza dei marker, coerenza
  dei default fra le due implementazioni): la loro logica va verificata su
  Windows.
- **La versione Windows non è stata provata su Windows.** `pi-conf.ps1` è
  stato eseguito con PowerShell 7 su macOS; il comportamento di Windows
  PowerShell 5.1 (in particolare `RawUI.ReadKey` per la lettura della API key)
  non è stato verificato su una sessione Windows reale.
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
- **`cost` resta a zero** finché non lo editi a mano.
- **Nessuna CI**: la suite passa solo se qualcuno la lancia.

---

<div align="center">

**MIT** · [EULA v1.3](EULA.md) ([EN](EULA.en.md)) · rilascio [`v0.4.1`](https://github.com/ALF-Robotics/pi-configurator/releases) · [🌐 pagina di supporto](https://alf-robotics.github.io/pi-configurator/)

<sub>🇮🇹 <b>Italiano</b> · 🇬🇧 <a href="README.en.md">English</a></sub>

</div>
