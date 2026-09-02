# Third-party data notice

## Lycoris deepwoken-rewrite timing data

CLAW MARK's `data/lycoris-timings.json` is a converted timing-data artifact derived from the public [Lycoris deepwoken-rewrite repository](https://git.blastbrean.com/lycoris/deepwoken-rewrite), pinned to upstream commit `ac1209b2fbd83a68338746e2e1e78a7b918fd273`. CLAW's native block/deflect bridge also follows Lycoris's documented KeyHandler hashing, input-state mirroring, and queued-block behavior in a smaller independently structured module.

Lycoris and its original timing data are by Blastbrean and the Lycoris contributors. The upstream project is publicly released for community use and forking; CLAW retains this notice and source link as attribution. CLAW does not vendor Lycoris implementation source. Its converter produces CLAW's independent timing-profile schema, and CLAW's runtime, validation, scheduling, UI, and fallback logic are maintained separately.
