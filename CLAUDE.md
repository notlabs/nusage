# Working here

## Options

Offer only options you would defend choosing. An option listed for completeness, as a
contrast, or to make another look better is not a choice. Including one costs the reader
the trust that the others are real, and makes every analysis harder to read. Leave such
options out entirely; don't list them as ruled out either. When only one option is real,
say so and give it.

## Settled

Don't reopen these or offer alternatives to them. Code that breaks one is a bug to fix,
not a precedent.

- The catalog never redistributes upstream binaries. It publishes specs, overlays and
  schemas; installing a tool joins them to the upstream artifact, which keeps its own
  checksums and attestations.
- A catalog tool's typed commands need no `use`. Declaring the tool in mise is the
  dependency, and calling the tool gets its typed command.
- The base layer is Nushell integrated with usage, and nothing else: it is not coupled to
  mise. The mise integration is a layer on the base layer's primitives, and may depend on
  jj.
