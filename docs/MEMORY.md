# Memory layer: from recordings to something you can trust

*Design intent only. None of this is built yet. The host today stops at transcripts, SQLite FTS5
search and daily Markdown ([`host/`](../host/README.md)).*

The product is **capture plus memory you can trust**, not a recorder. A wrong memory is worse
than none: it gets repeated with confidence. So the rules below matter more than the model
behind them.

## Rules

1. **Provenance on everything.** Every fact, task or summary line links back to its source:
   chunk ID, audio offset and the transcript span. You must be able to press play on the moment
   it came from. Nothing without a source gets stored. (Boswell refuses any item that doesn't cite
   its clips, after its store ended up with 74 facts nobody could check:
   [README](https://github.com/leakydata/boswell).)
2. **Say what kind of claim it is.** Each item carries one of these:

   | Kind | Meaning | Example |
   |---|---|---|
   | **said** | Someone said it; the recording proves only that | "Sam said the invoice was paid" |
   | **verified** | Checked against something outside the recording | Invoice marked paid in the accounts |
   | **committed** | A promise by a named person, with a due date if one was said | "I'll send the quote by Friday" (me) |
   | **inferred** | The AI's reading, not anyone's words | "Seems worried about the deadline" |

   Inferred items are never shown as if they were quotes.
3. **Who said it.** Each item names the speaker as the transcript shows them. An unnamed
   diariser label (`SPEAKER_01`) isn't a person.
4. **Guard against false memories.** Watch for three failure modes:
   - things never said: hallucinated transcript text, often in silence or noise;
   - TV, radio or podcast speech attributed to the wearer or to people in the room;
   - a summary that merges two conversations.

   Defences: server-side VAD before transcription; tagging voices as `media` and excluding them
   from facts; and judging each line by who said it, not the whole clip. (Boswell found a
   per-clip rule blocked the owner's own words when a video was playing alongside them.)
5. **Correctable and deletable.** You can edit any item, re-label its kind, or delete it. Deleting
   a time range removes the audio, the transcript and every item derived from it. That is also
   the legal off-switch: someone asks to be removed ([LEGAL](LEGAL.md)).
6. **Local by default.** It is stored and searched on your own machines. Sending text to a hosted
   model is an explicit, per-use choice.

## Success metrics

| Metric | How to measure it |
|---|---|
| Capture reliability | Hours recorded ÷ hours worn; gaps over 1 s per day ([Gate 3](BUILD-SIMULATION.md)) |
| Transcription on what matters | Names and commitments right in the placement test (Gate 2) and in a weekly spot check |
| Retrieval days later | "What did I agree with Sam on Tuesday?" answered correctly **with the clip as evidence** |
| False-memory rate | Items that fail a play-the-source check, per 100 sampled |
| Friction | Minutes a week spent fixing, charging or syncing |

## Later, optional

- **Other context sources:** calendar, email and notes, to turn "said" into "verified" and to
  name speakers. Each one is opt-in and stays local.
- **Agent access over MCP:** expose search, get-clip and the said/verified/committed/inferred
  items as an MCP server, so Claude or another agent can answer from the archive. Answers must
  cite their clips, and write tools obey rules 1–3.
