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
  generally need **every party's consent**, unless a narrow exception applies.
- **NSW in detail** (*Surveillance Devices Act 2007*, s 7(3)(b)): a party to the
  conversation may record it without the others' consent only if **either**
  (i) the recording is reasonably necessary to protect that party's lawful
  interests, **or** (ii) it is not made for the purpose of communicating or
  publishing the conversation, or a report of it, to people who weren't parties.
  Limb (ii) reads as if a private memory aid could fit, but treat both limbs as
  narrow: whether an always-on personal archive is "not made for the purpose of
  communicating" is untested, it covers only conversations you're part of, and
  sharing a clip or transcript later is a separate offence (s 11) with its own
  narrow exceptions. The advice doesn't change: get consent, or pause. Maximum penalty for an individual: 100 penalty units
  or 5 years' imprisonment, or both (500 penalty units for a corporation), per
  secondary legal summaries; we couldn't load the official text to check it.
  We haven't checked whether the TAS or ACT Acts have a similar limb.
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

1. **A physical privacy switch, enforced by firmware.** Flick it when you walk
   into a meeting, a shop or a friend's house. The switch is read by the firmware
   (D5), which stops the PDM and cuts the external mic's power (D2 LOW), with the
   XIAO's onboard mic held off (P1.10 LOW), so the mic is unpowered, not just muted
   ([WIRING §4](WIRING.md)). **Limitation:** this
   is only as good as the firmware. A bug or a malicious image could ignore the
   switch. Signed images and owner-built firmware reduce that risk but don't
   remove it. A switch that interrupts mic power in hardware is a possible v2
   upgrade: now that the mic is on its own small board, a double-pole switch can
   break its supply directly ([WIRING §4](WIRING.md)).
2. **A visible recording indicator, required whenever it records unplugged.**
   A low-brightness LED (blinking, µA average) that is on whenever the capsule is
   worn and recording, so people around you can tell. It also helps socially.
   Plugged in on the bedside stand, in your own bedroom, it may be dimmed or turned
   off at night.
   ([WIRING §5](WIRING.md))
3. **Consent-friendly defaults.** A "solo mode" is the expected everyday use:
   your own voice notes, thinking out loud, sleep audio in your own room. Record
   others only when they know and agree.
4. **Encrypted at rest, private by default.** Nothing leaves your own machines.
   A lost pendant reveals nothing (see [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md)).
5. **Server-side tools to delete or redact** a time range when someone asks.

## Sources (verify current versions)

- NSW: https://legislation.nsw.gov.au/view/html/inforce/current/act-2007-064
  (s 7(3)(b) limbs as summarised by Sydney Criminal Lawyers,
  https://www.sydneycriminallawyers.com.au/?p=8351; penalties as summarised by
  Go To Court, https://www.gotocourt.com.au/criminal-law/nsw/listening-devices-new-south-wales/)
- VIC: https://www.legislation.vic.gov.au/in-force/acts/surveillance-devices-act-1999
- QLD: https://www.legislation.qld.gov.au/view/html/inforce/current/act-1971-050
- WA: https://www.legislation.wa.gov.au
- SA: https://www.legislation.sa.gov.au
- TAS: https://www.legislation.tas.gov.au/view/html/inforce/current/act-1991-021
- ACT: https://www.legislation.act.gov.au/a/1992-57/
- NT: https://legislation.nt.gov.au
- NSW Workplace Surveillance Act 2005: https://legislation.nsw.gov.au/view/html/inforce/current/act-2005-047
- Privacy Act 1988 (Cth): https://www.legislation.gov.au/C2004A03712/latest
