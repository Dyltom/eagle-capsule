# Recording law in Australia: read before you wear one

**Not legal advice.** This is a builder's summary to shape the design. The
section numbers were compiled from memory and have **not yet been checked
against the current legislation**. Check the Act for your state, or ask a
lawyer, before wearing this around other people.

## The short version

- Recording **conversations you are not part of** (people at the next table, a
  colleague's phone call, your housemates in the next room) is an offence **in
  every state and territory**.
- In **NSW, WA, SA, TAS and the ACT**, even if you are *in* the conversation, you
  generally need **every party's consent**. The exceptions are narrow (e.g.
  "reasonably necessary to protect your lawful interests"), and routine
  life-logging is not one of them.
- In **VIC, QLD and the NT**, a party may record a conversation they are part of,
  but **sharing or publishing** it is still restricted.
- A "private conversation" can happen in public. A quiet chat in a café still
  counts.
- **Work:** your employer's policies, confidentiality duties and client
  agreements apply. Assume the device must be paused at work unless the workplace
  explicitly agrees.
- The Privacy Act 1988 (Cth) generally exempts purely personal or household use
  (s 16). That stops applying if the data is used commercially or handled by a
  business.

| Jurisdiction | Act | A party recording without everyone's consent |
|---|---|---|
| NSW | Surveillance Devices Act 2007 | ❌ generally not allowed |
| VIC | Surveillance Devices Act 1999 | ✅ allowed (publication restricted) |
| QLD | Invasion of Privacy Act 1971 | ✅ allowed (publication restricted) |
| WA | Surveillance Devices Act 1998 | ❌ generally not allowed |
| SA | Surveillance Devices Act 2016 | ❌ generally not allowed |
| TAS | Listening Devices Act 1991 | ❌ generally not allowed |
| ACT | Listening Devices Act 1992 | ❌ generally not allowed |
| NT | Surveillance Devices Act 2007 | ✅ allowed (publication restricted) |

## How this shapes the design (non-negotiable features)

1. **A hardware pause.** The slide switch cuts recording in hardware (it gates
   the mic and is read by the firmware), so you can flick it off when you walk
   into a meeting, a shop or a friend's house. Off really means off.
2. **A visible indicator.** An optional low-brightness LED, or a physical flag
   visible when the switch is on, so people around you can tell. It also helps
   socially.
3. **Consent-friendly defaults.** A "solo mode" is the expected everyday use:
   your own voice notes, thinking out loud, sleep audio in your own room. Record
   others only when they know and agree.
4. **Encrypted at rest, private by default.** Nothing leaves your own machines.
   A lost pendant reveals nothing (see [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md)).
5. **Server-side tools to delete or redact** a time range when someone asks.

## Sources (verify current versions)

- NSW: https://legislation.nsw.gov.au/view/html/inforce/current/act-2007-064
- VIC: https://www.legislation.vic.gov.au/in-force/acts/surveillance-devices-act-1999
- QLD: https://www.legislation.qld.gov.au/view/html/inforce/current/act-1971-050
- WA: https://www.legislation.wa.gov.au
- SA: https://www.legislation.sa.gov.au
- TAS: https://www.legislation.tas.gov.au/view/html/inforce/current/act-1991-021
- ACT: https://www.legislation.act.gov.au/a/1992-57/
- NT: https://legislation.nt.gov.au
- NSW Workplace Surveillance Act 2005: https://legislation.nsw.gov.au/view/html/inforce/current/act-2005-047
- Privacy Act 1988 (Cth): https://www.legislation.gov.au/C2004A03712/latest
