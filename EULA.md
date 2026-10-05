# EULA — pi-configurator

**Versione 1.1 — 2026-10-04**

> 🇮🇹 **Italiano** · 🇬🇧 [English](EULA.en.md)

> **Testo autorevole.** Questo documento in lingua italiana fa prevalere in caso
> di divergenza interpretativa (vedi § 12). La versione inglese è una traduzione
> di cortesia, priva di autonoma efficacia giuridica, e può divergere solo per
> imprecisione di traduzione.

> **1.0 → 1.1**: § 5 e § 6 aggiornati dopo la risoluzione delle issue #1 e #2
> (merge non distruttivo, backup automatico, mascheramento della chiave in
> anteprima, allineamento delle due implementazioni sul file non leggibile).
> Nessuna modifica a § 9 e § 10, che restano invariate rispetto alla 1.0.

Contratto di licenza utente finale per il software **pi-configurator**.

> Questo documento coesiste con la licenza open `MIT` presente nel file
> [`LICENSE`](LICENSE). I due non si sostituiscono: la licenza MIT disciplina
> l'uso, la modifica e la redistribuzione del **codice sorgente**; le presenti
> condizioni disciplinano l'**uso del software come strumento operativo**,
> incluse le credenziali che vi vengono affidate e le responsabilità che ne
> derivano. Accettando le presenti condizioni accetti anche i termini della MIT.

---

## 1. Titolari e software

| | |
|---|---|
| Titolari dei diritti | **Drago Solutions e Oraclum-X** (di seguito anche "i Titolari" o "i Licenzianti") |
| Software | pi-configurator — script interattivi `pi-conf.sh` (bash) e `pi-conf.ps1` (PowerShell) |
| Versione del software | quella installata; il repository non pubblica tag di versione |
| Licenza del codice | MIT — file `LICENSE` |
| Contatto | `<EMAIL>` |
| Oraclum-X S.r.l. | P.IVA IT04506720244 |

Drago Solutions e Oraclum-X sono soggetti distinti. Ogni riferimento a "i
Titolari" in questo documento si riferisce **congiuntamente** a entrambi, che
sono co-titolari delle medesime obbligazioni.

## 2. Accettazione

L'uso del software, anche parziale, costituisce accettazione integrale delle
presenti condizioni (art. 1341 c.c.).

Ai sensi degli artt. **1341 e 1342 del Codice Civile**, ciascuna clausola
contrattuale è portata a conoscenza del contraente in modo chiaro e completo,
è oggettivamente interpretabile ed è stata specificamente approvata. Chi
utilizza il software dichiara:

- di aver **letto integralmente** le presenti condizioni prima dell'accettazione;
- di aver avuto la **concreta possibilità di esaminarle** in un momento
  precedente e separato rispetto all'accettazione (art. 1342 c.c.);
- di **approvare specificamente** le clausole contrassegnate come
  *(clausola da approvazione specifica)*.

Il contraente può **rifiutare** l'accettazione e in tal caso deve cessare
l'uso del software, senza penali.

## 3. Licenza concessa

I Licenzianti concedono al contraente una licenza **non esclusiva, gratuita,
non trasferibile e revocabile** per:

1. scaricare e installare il software;
2. eseguirlo per le finalità interne del contraente;
3. modificarne il funzionamento per esigenze proprie;
4. conservare la licenza MIT in tutte le copie o porzioni sostanziali.

La licenza è **personale** e non può essere sublicenziata, ceduta o trasferita,
anche parzialmente e anche a titolo gratuito, senza il consenso scritto
prevento dei Licenzianti.

## 4. Restrizioni

È vietato, salvo autorizzazione scritta dei Licenzianti:

- decompilare, disassemblare o effettuare reverse engineering del software, salvo
  quanto consentito dall'art. 69 del d.lgs. 231/2001;
- rimuovere o occultare gli avvisi relativi ai diritti di autore e alla
  licenza;
- vendere, noleggiare, cedere o distribuire il software, in forma originale o
  modificata, come prodotto a sé stante;
- utilizzare il software per violare leggi, regolamenti o diritti di terzi.

La licenza MIT **non revoca** per effetto delle presenti condizioni: revoca
della licenza d'uso e decadenza della licenza open restano distinte, e la
revoca della prima non opera retroattamente sulle copie legittimamente
distribuite sotto MIT.

## 5. Credenziali e sicurezza

*(clausola da approvazione specifica)*

Il software **scrive le credenziali API in chiaro** nel file di configurazione
`models.json`, che l'utente è tenuto a proteggere.

Il contraente assume la **responsabilità esclusiva** per:

- custodia e riservatezza delle API key immesse;
- correttezza dei permessi del file `models.json` — lo script imposta il modo
  `0600` su sistemi Unix; su Windows la protezione dipende dagli ACL predefiniti
  del profilo utente e **non è imposta dallo script**;
- custodia dei **backup** effettuati prima di ogni nuova esecuzione.

I Licenzianti non trattano, non ricevono e non conservano alcuna credenziale.
Le credenziali restano interamente sotto il controllo del contraente.

L'anteprima a terminale **maschera** la `apiKey` (`••••••••` più le ultime
4 cifre); il valore in chiaro viene scritto solo nel file. I Licenzianti non
rispondono comunque di eventuali danni derivanti dalla divulgazione di
`models.json` — per esempio condivisione del file, copia su sistemi non
protetti o inclusione in backup non cifrati.

## 6. Limiti noti e responsabilità del contraente

*(clausola da approvazione specifica)*

I Licenzianti rendono noti i seguenti limiti del software nella versione
corrente. La loro conoscenza da parte del contraente è requisito di
accettazione.

**6.1 Sovrascrittura del provider — risolto.** Nelle versioni precedenti un
re-run sullo stesso nome di profilo riscriveva il provider per intero,
perdendo `apiKey`, `promptCache`, `headers`, `compat`, `cost` e i modelli
aggiuntivi; il flusso più comune — lasciare la API key vuota perché verrà
configurata dopo — cancellava proprio la credenziale salvata. Il merge è ora
non distruttivo e i campi non gestiti vengono conservati. Chi usa una versione
anteriore deve considerare la propria `models.json` come potenzialmente
danneggiata da ogni esecuzione pregressa.

**6.2 Backup — parzialmente risolto.** Prima di ogni scrittura su un file
esistente viene creata una copia in `models.json.bak`. Il backup **non** viene
creato se il file non esiste, viene **sovrascritto** a ogni nuova esecuzione e
non riflette le modifiche apportate a mano tra un'esecuzione e l'altra.

**6.3 Verifica non attendibile con variabili d'ambiente.** Se sono impostate
`PI_CONF_FILE` o `PI_CODING_AGENT_DIR`, il controllo finale di autenticazione
non riflette il file scritto dallo script.

**6.4 Comportamenti diversi tra le due implementazioni.** `pi-conf.sh` e
`pi-conf.ps1` non si comportano allo stesso modo in ogni caso: `PI_BIN` ha la
precedenza in PowerShell, mentre in bash viene usato solo se `pi` non è già in
PATH. La gestione del file non leggibile è allineata — entrambe le
implementazioni abortiscono senza scrivere — ma il resto non è coperto da test.

**6.5 Copertura dei test.** I test automatici esercitano `pi-conf.sh`
eseguendolo. `pi-conf.ps1` non è coperto da test comportamentali: la sua
correttezza su Windows **non è verificata automaticamente** e richiede una
esecuzione manuale.

**6.6 Valori di costo a zero.** I campi `cost` generati sono sempre `0` e non
rappresentano il prezzo effettivo del provider. `input: ["text"]` è fisso e non
espone l'input multimodale.

Il contraente dichiara di essere stato informato dei limiti sopra elencati e di
essere consapevole che il backup di cui al § 6.2 è l'unica rete di sicurezza
fornita dal software.

## 7. Dati personali e GDPR

Il software opera **esclusivamente sulla macchina del contraente** e non
trasmette dati a server dei Licenzianti. Non è presente alcun telemetria,
analytics, crash reporting o meccanismo di raccolta dati.

I Licenzianti **non sono titolari del trattamento** dei dati personali
eventualmente gestiti dal contraente tramite le credenziali configurate: il
trattamento compete al contraente in qualità di titolare, che ne assume la
responsabilità in proprio.

Il contraente è tenuto a:

- trattare le credenziali conformemente al Reg. (UE) 2016/679 e alla normativa
  nazionale attuativa;
- non immettere dati personali di terzi in contesti non autorizzati;
- adottare misure tecniche e organizzative adeguate (art. 32 GDPR) a proteggere
  `models.json`.

## 8. Utilizzo dei provider di modelli linguistici

Il software configura client per provider di modelli linguistici di terze
parti. Esso **non effettua** chiamate a modelli, non genera contenuti e non
interviene nel trattamento delle informazioni inoltrate a detti provider.

Il contraente è l'unico responsabile di:

- disporre di un'autorizzazione e di una base giuridica idonee per ogni uso
  dei modelli linguistici configurati, incluse le finalità consentite dal
  Reg. (UE) 2024/1689 (AI Act) e gli eventuali obblighi di trasparenza;
- rispettare i termini di servizio del provider configurato;
- non utilizzare il software per finalità vietate dalla legge.

## 9. Esclusione di garanzia

*(clausola da approvazione specifica)*

Il software è fornito **"così com'è" e "così come disponibile"**, senza
garanzia di alcun tipo, espressa o implicita, ivi a titolo di **merciabilità**,
**idoneità ad un uso specifico**, **non violazione di diritti** e **accuratezza**
dei valori di default proposti (context window, max output tokens, mapping
delle API).

I Licenzianti non garantiscono che il software sia esente da errori, che
funzioni in ogni ambiente, o che rimanga disponibile senza interruzioni.

## 10. Limitazione di responsabilità

*(clausola da approvazione specifica)*

Nei limiti massimi consentiti dalla legge applicabile, la **responsabilità
totale cumulata** dei Licenzianti — per qualsiasi preteso derivante dal o
relativo al software o al suo utilizzo — è limitata all'importo effettivamente
pagato dal contraente per il software, che per la licenza MIT è **zero**.

I Licenzianti **non rispondono** di:

- perdita o corruzione di `models.json` o di qualsiasi altro file;
- perdita di `models.json`, di credenziali, modelli, `cost` o `promptCache` per
  qualsiasi causa, ivi compresa la perdita o l'insufficienza del backup di cui
  al § 6.2;
- costi sostenuti presso provider di terze parti, ad esempio consumi API
  eccedenti, fatturati direttamente al contraente;
- danni indiretti, incidentali, speciali, consequenziali, perdita di profitto,
  perdita di dati o perdita di opportunità, **anche se tali danni fossero stati
  possibili o prevedibili**.

Nessuna limitazione del presente § 10 esclude o limita la responsabilità per
dolo o colpa grave, né per danni derivanti da lesioni alla persona, nei limiti
impostati dalla legge.

## 11. Durata, revoca e cessazione

La presente licenza ha durata **indefinita** e decorre dall'accettazione.

Cessa automaticamente, senza preavviso, in caso di:

- cancellazione della licenza open MIT da parte del contraente;
- violazione grave di una qualsiasi delle condizioni dei § 4, § 5 o § 6.

Il contraente può cessare l'uso in qualsiasi momento, senza penali, con
l'obbligo di eliminare le copie e di proteggere o cancellare le credenziali
configurate.

Alla cessazione restano applicabili i § 5, 10 e 12.

## 12. Legge applicabile e foro competente

*(clausola da approvazione specifica)*

Il presente contratto è regolato dalla **legge italiana**.

Per i consumatori resta ferma la competenza del foro del luogo di residenza o
di domicilio elettivo prevista dall'art. 2 c.p.c. Per le parti professionali,
la competenza esclusiva spetta al Foro di **`<CITTÀ>`**.

Le presenti condizioni sono redatte in lingua italiana; in caso di
divergenza interpretativa fa prevalente il testo italiano.

## 13. Modifiche

I Licenzianti possono modificare le presenti condizioni. La versione vigente è
quella pubblicata nel repository alla data dell'accettazione, identificata dalla
versione e dalla data in testata. Le modifiche sostanziali — in particolare
quelle relative a § 9 e § 10 — richiedono una nuova accettazione esplicita.

## 14. Documenti collegati

- [`LICENSE`](LICENSE) — licenza MIT del codice sorgente
- [`EULA.en.md`](EULA.en.md) — le presenti condizioni in inglese (traduzione)
- [`README.md`](README.md) — funzionamento, dipendenze e limiti noti
- [`README.en.md`](README.en.md) — funzionamento, dipendenze e limiti noti (inglese)
- [`tests/pi-conf-test.sh`](tests/pi-conf-test.sh) — suite comportamentale
- Issue [#1](https://github.com/ALF-Robotics/pi-configurator/issues/1) — sovrascrittura del provider, **risolta** (cfr. § 6.1)
- Issue [#2](https://github.com/ALF-Robotics/pi-configurator/issues/2) — chiave in chiaro nell'anteprima, **risolta** (cfr. § 5)

---

*Documento redatto il 2026-10-04. I segnaposto `<EMAIL>` e `<CITTÀ>` vanno
completati prima della diffusione. Prima di utilizzare questo EULA in un
contesto commerciale o contrattuale è opportuno farlo valutare da un
professionista abilitato.*
