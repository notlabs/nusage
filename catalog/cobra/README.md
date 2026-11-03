# Cobra

The usage spec of a Go binary built with Cobra, read from its command tree through [usage's Cobra adapter](https://github.com/jdx/usage/tree/main/integrations/cobra) by an extractor under `../lib/<bin>/spec/`, which pins the tool and the adapter.
An extractor that needs packages the tool keeps internal builds inside a checkout of the tool, as its own header says.
Go is needed to write the spec, not to use the module.

The adapter drops bare required positionals, such as `SERVICE COMMAND` in Compose's `exec`, and keeps no pflag slice or repetition types, so those arguments are missing or untyped in the spec.
What else it gets wrong, each extractor corrects, and its comments say what and until when.
