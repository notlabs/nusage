# TypeSafe AI

The [TypeSafe AI](https://typesafe.ai) API as a Nushell module: `typesafe list-models`, and
`typesafe system-one`, which takes a request as its input and returns the typed answers. A
System One model answers named questions about content and returns one typed answer per
question rather than text: a yes/no probability (`noul`), a choice with its probabilities, a
score against a rubric, a box in an image.

```nu
use typesafe *

$env.TYPESAFE_TOKEN = $env.TYPESAFE_API_KEY
typesafe list-models | get models | select name release_date
{
    model: jev-latest
    state: "I was charged twice. Please fix this ASAP."
    questions: {
        billing: {type: noul, instructions: "Is this ticket about billing?"}
        category: {type: choice, criteria: {billing: null, technical: null, other: null}}
        urgency: {type: score, criteria: ["Can wait" "This week" "Today"]}
    }
} | typesafe system-one | get answers
```

The key is `$env.TYPESAFE_TOKEN`, sent as a bearer token, as the module's helpers say;
`$env.TYPESAFE_URL` points the module elsewhere, at a stand-in or a proxy. The request record
is the body: `model`, `state` and `questions` are required, `assets` may be added.

## The document

`openapi.yaml` is the source of the package. The API publishes its own OpenAPI document at
`api.typesafe.ai/openapi.json`, which the official Python SDK's wire models are generated
from; this document is written from those models, `typesafe-sdk` 0.7.5 on PyPI, with their
descriptions, and from what the SDKs' transports send, `@typesafe-ai/sdk` 0.7.0 on npm for
the TypeScript one: the two paths, the bearer authentication, the images header. Where the
published document and this one differ, the published one is right; replace this one with it
and run `spec` again.

Images travel as `multipart/form-data`, a JSON `request` part followed by one part per image,
which the SDKs build; the document describes the JSON body and the module sends it, so an
image goes as `data_base64` in `assets`, with the `TypeSafe-Danger-Zone-Images` header the
flag sets. The SDKs also compress bodies and retry; the module does neither.

## Check

`check.nu` drives the module against `stub.py`, a stand-in that answers as the schemas say,
on a port of its own: what each wrapper sends, where the token goes, and the decoding of the
response, with no key and no network. It needs `python3`. With `TYPESAFE_API_KEY` set, it
also lists the models from the service.

## Regenerate

From the repository root:

```sh
mise run //catalog:spec typesafe
mise run //catalog:generate typesafe
mise run //catalog:check typesafe
```

`spec` writes `typesafe.usage.kdl`, `typesafe.http.kdl` and `schemas/*.schema.json` from the
document through `openapi-usage`; `check` writes them again and holds the committed ones to
the document.
