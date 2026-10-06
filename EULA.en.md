# EULA — pi-configurator

**Version 1.2 — 2026-10-06**

> 🇮🇹 [Italiano](EULA.md) · 🇬🇧 **English**

> **English translation** prepared on 2026-10-05 from the Italian original
> v1.1 of 2026-10-04. The Italian text is the authoritative version: in case of
> any interpretive divergence, the Italian prevails (see § 12).

> **1.1 → 1.2**: § 6.6 updated. The limit “`input: ["text"]` is fixed and does
> not expose multimodal input” has been **resolved**: the script now writes
> `input: ["text", "image"]` by default, accepts `--input` to choose explicitly,
> and preserves the `input` already present when the flag is omitted. These
> changes are only less restrictive than 1.1: no new limit, no change to § 9 and
> § 10.
>
> **1.0 → 1.1**: § 5 and § 6 updated after the resolution of issues #1 and #2
> (non-destructive merge, automatic backup, key masking in the preview,
> alignment of the two implementations on an unreadable file).
> No change to § 9 and § 10, which remain unchanged with respect to 1.0.

End User License Agreement for the **pi-configurator** software.

> This document coexists with the open source `MIT` license contained in the
> [`LICENSE`](LICENSE) file. The two do not replace each other: the MIT license
> governs the use, modification and redistribution of the **source code**; these
> terms govern the **use of the software as an operational tool**, including the
> credentials entrusted to it and the responsibilities arising from that. By
> accepting these terms you also accept the terms of the MIT license.

---

## 1. Rights Holders and software

| | |
|---|---|
| Rights holders | **Drago Solutions and Oraclum-X** (hereinafter also "the Rights Holders" or "the Licensors") |
| Software | pi-configurator — interactive scripts `pi-conf.sh` (bash) and `pi-conf.ps1` (PowerShell) |
| Software version | the one installed; the repository publishes no version tags |
| Code license | MIT — `LICENSE` file |
| Contact | `<EMAIL>` |
| Oraclum-X S.r.l. | VAT No. IT04506720244 |

Drago Solutions and Oraclum-X are separate entities. Every reference to "the
Rights Holders" in this document refers **jointly** to both, who are
co-holders of the same obligations.

## 2. Acceptance

Use of the software, even partial, constitutes full acceptance of these terms
(Art. 1341 of the Italian Civil Code).

Pursuant to Articles **1341 and 1342 of the Civil Code**, each contractual
clause has been brought to the contracting party's attention in a clear and
complete manner, is objectively interpretable, and has been specifically
approved. Anyone using the software declares that they:

- have **read these terms in full** before accepting them;
- have had the **concrete opportunity to examine them** at a moment prior to and
  separate from acceptance (Art. 1342 of the Civil Code);
- **specifically approve** the clauses marked as
  *(clause requiring specific approval)*.

The contracting party may **refuse** acceptance, in which case they must cease
using the software, without penalty.

## 3. License granted

The Licensors grant the contracting party a **non-exclusive, royalty-free,
non-transferable and revocable** license to:

1. download and install the software;
2. run it for the contracting party's internal purposes;
3. modify its operation for their own needs;
4. retain the MIT license in all copies or substantial portions.

The license is **personal** and may not be sublicensed, assigned or transferred,
even partially and even for free, without the prior written consent of the
Licensors.

## 4. Restrictions

It is forbidden, absent written authorization from the Licensors, to:

- decompile, disassemble or reverse engineer the software, except as permitted
  by Art. 69 of Legislative Decree 231/2001;
- remove or conceal the notices relating to copyright and to the license;
- sell, rent out, assign or distribute the software, in original or modified
  form, as a standalone product;
- use the software to violate laws, regulations or third-party rights.

The MIT license **is not revoked** by these terms: revocation of the use license
and lapse of the open source license remain distinct, and revocation of the
former does not operate retroactively on copies lawfully distributed under MIT.

## 5. Credentials and security

*(clause requiring specific approval)*

The software **writes API credentials in clear** into the `models.json`
configuration file, which the user is required to protect.

The contracting party assumes **sole responsibility** for:

- custody and confidentiality of the API keys entered;
- correctness of the permissions of the `models.json` file — the script sets
  mode `0600` on Unix systems; on Windows the protection depends on the default
  ACLs of the user profile and is **not enforced by the script**;
- custody of the **backups** made before each new run.

The Licensors do not process, receive or store any credential. The credentials
remain entirely under the contracting party's control.

The terminal preview **masks** the `apiKey` (`••••••••` plus the last 4 digits);
the clear value is written only to the file. The Licensors nevertheless
assume no liability for any damage arising from the disclosure of
`models.json` — for example sharing the file, copying it onto unprotected
systems, or including it in unencrypted backups.

## 6. Known limits and the contracting party's responsibility

*(clause requiring specific approval)*

The Licensors make the following limits of the software in the current version
known. The contracting party's knowledge of them is a condition of acceptance.

**6.1 Provider overwrite — resolved.** In earlier versions, a re-run on the same
profile name rewrote the provider in full, losing `apiKey`, `promptCache`,
`headers`, `compat`, `cost` and any additional models; the most common flow —
leaving the API key empty because it will be configured later — wiped out
precisely the saved credential. The merge is now non-destructive and unmanaged
fields are preserved. Anyone using an earlier version must consider their own
`models.json` potentially damaged by every prior run.

**6.2 Backup — partially resolved.** Before each write to an existing file, a
copy is made to `models.json.bak`. The backup is **not** created if the file
does not exist, is **overwritten** on each new run, and does not reflect changes
made by hand between one run and the next.

**6.3 Unreliable verification when environment variables are set.** If
`PI_CONF_FILE` or `PI_CODING_AGENT_DIR` are set, the final authentication check
does not reflect the file written by the script.

**6.4 Different behaviour between the two implementations.** `pi-conf.sh` and
`pi-conf.ps1` do not behave the same way in every case: `PI_BIN` takes
precedence in PowerShell, whereas in bash it is used only if `pi` is not already
in PATH. Unreadable-file handling is aligned — both implementations abort
without writing — but the rest is not covered by tests.

**6.5 Test coverage.** The automated tests exercise `pi-conf.sh` by executing
it. `pi-conf.ps1` is not covered by behavioural tests: its correctness on
Windows is **not automatically verified** and requires a manual run.

**6.6 Cost values set to zero — multimodal input resolved.** The generated
`cost` fields are always `0` and do not represent the provider's actual price.
As to multimodal input, the limit was **removed as of 1.2**: the script writes
`input: ["text", "image"]` by default, the `--input` flag allows choosing
explicitly (`--input text` for text only), and the `input` already present in a
profile is preserved when the flag is not used. Only the modalities allowed by
pi's type, `text` and `image`, remain valid: any other value is rejected before
anything is written.

The contracting party declares that they have been informed of the limits
listed above, and that they are aware that the backup referred to in § 6.2 is
the only safety net provided by the software.

## 7. Personal data and GDPR

The software operates **exclusively on the contracting party's machine** and
transmits no data to the Licensors' servers. There is no telemetry, analytics,
crash reporting or data collection mechanism of any kind.

The Licensors are **not data controllers** for any personal data the
contracting party may process through the configured credentials: that
processing belongs to the contracting party in their capacity as data
controller, who assumes responsibility for it directly.

The contracting party is required to:

- process the credentials in accordance with Regulation (EU) 2016/679 and
  applicable national implementing legislation;
- not enter third-party personal data into unauthorised contexts;
- adopt appropriate technical and organisational measures (Art. 32 GDPR) to
  protect `models.json`.

## 8. Use of language model providers

The software configures clients for third-party language model providers. It
**does not make** calls to models, does not generate content, and does not
intervene in the processing of information forwarded to those providers.

The contracting party is solely responsible for:

- holding a suitable authorisation and legal basis for every use of the
  configured language models, including the purposes permitted by Regulation
  (EU) 2024/1689 (AI Act) and any transparency obligations;
- complying with the terms of service of the configured provider;
- not using the software for purposes prohibited by law.

## 9. Disclaimer of warranties

*(clause requiring specific approval)*

The software is provided **"as is" and "as available"**, without warranty of
any kind, express or implied, including but not limited to **merchantability**,
**fitness for a particular purpose**, **non-infringement** and **accuracy** of
the proposed default values (context window, max output tokens, API mapping).

The Licensors do not warrant that the software is free of errors, that it will
function in every environment, or that it will remain available without
interruption.

## 10. Limitation of liability

*(clause requiring specific approval)*

To the fullest extent permitted by applicable law, the Licensors' **total
aggregate liability** — for any claim arising out of or relating to the
software or its use — is limited to the amount actually paid by the contracting
party for the software, which for the MIT license is **zero**.

The Licensors are **not liable** for:

- loss of or corruption of `models.json` or of any other file;
- loss of `models.json`, credentials, models, `cost` or `promptCache` for any
  cause, including the loss or insufficiency of the backup referred to in
  § 6.2;
- costs incurred with third-party providers, for example excess API usage
  billed directly to the contracting party;
- indirect, incidental, special or consequential damages, loss of profit, loss
  of data or loss of opportunity, **even if such damages were possible or
  foreseeable**.

No limitation in this § 10 excludes or limits liability for wilful misconduct
or gross negligence, nor for damages resulting from personal injury, within the
limits imposed by law.

## 11. Term, revocation and termination

This license is of **indefinite** duration and starts from acceptance.

It terminates automatically, without notice, in the event of:

- cancellation of the open source MIT license by the contracting party;
- serious violation of any of the conditions in § 4, § 5 or § 6.

The contracting party may cease using the software at any time, without
penalty, with the obligation to delete the copies and to protect or delete the
configured credentials.

Upon termination, § 5, 10 and 12 remain applicable.

## 12. Governing law and jurisdiction

*(clause requiring specific approval)*

This contract is governed by **Italian law**.

For consumers, the jurisdiction of the place of residence or elected domicile
provided for by Art. 2 of the Code of Civil Procedure remains unaffected. For
professional parties, exclusive jurisdiction belongs to the Court of
**`<CITY>`**.

These terms are drawn up in Italian; in case of interpretive divergence the
Italian text prevails. This English version is a convenience translation and
has no autonomous legal effect.

## 13. Amendments

The Licensors may amend these terms. The version in force is the one published
in the repository on the date of acceptance, identified by the version and date
in the header. Substantive amendments — in particular those relating to § 9 and
§ 10 — require a new explicit acceptance.

## 14. Related documents

- [`LICENSE`](LICENSE) — MIT license of the source code
- [`README.md`](README.md) — behaviour, dependencies and known limits (Italian)
- [`README.en.md`](README.en.md) — behaviour, dependencies and known limits (English)
- [`tests/pi-conf-test.sh`](tests/pi-conf-test.sh) — behavioural test suite
- Issue [#1](https://github.com/ALF-Robotics/pi-configurator/issues/1) — provider overwrite, **resolved** (see § 6.1)
- Issue [#2](https://github.com/ALF-Robotics/pi-configurator/issues/2) — key in clear in the preview, **resolved** (see § 5)

---

*Document drawn up on 2026-10-04, revision 1.2 on 2026-10-06; English translation on 2026-10-05. The
placeholders `<EMAIL>` and `<CITY>` must be completed before circulation.
Before using this EULA in a commercial or contractual context, it is advisable
to have it reviewed by a qualified professional.*
