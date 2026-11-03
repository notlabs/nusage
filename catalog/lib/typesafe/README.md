# TypeSafe AI

The [TypeSafe AI](https://typesafe.ai) API as a Nushell module: `typesafe list-models`, and `typesafe system-one`, which takes the request record as its input and returns one typed answer per question.

```nu
use typesafe *

$env.TYPESAFE_TOKEN = $env.TYPESAFE_API_KEY
{
    model: jev-latest
    state: "I was charged twice. Please fix this ASAP."
    questions: {billing: {type: noul, instructions: "Is this ticket about billing?"}}
} | typesafe system-one | get answers
```

The token is `$env.TYPESAFE_TOKEN`, sent as a bearer token; `$env.TYPESAFE_URL` sends the requests elsewhere.
Unlike the SDKs, the module sends JSON only, so an image goes as base64 in `assets`, with `--type-safe-danger-zone-images`, and it neither compresses a request nor retries one.

`openapi.yaml` was written by hand from the SDKs.
The API publishes its own document at `https://api.typesafe.ai/openapi.json`, which is right where the two differ.
