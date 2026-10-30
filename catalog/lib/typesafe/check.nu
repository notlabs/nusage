#!/usr/bin/env nu
# Drives the service's wrappers against `stub.py`, a stand-in for the API that answers as its
# schemas say, so the check holds the module to the mapping without a key or the network:
# the request each wrapper sends, where the credentials go, and the decoding of what comes
# back. The catalog's `check` runs this with `lib` included; it needs `python3`. With
# `TYPESAFE_API_KEY` in the environment, the models are also listed from the service itself.
use std/assert
use typesafe *

const here = path self | path dirname

let dir = mktemp --directory
let port_file = $dir | path join port
let server = job spawn { ^python3 ($here | path join stub.py) $port_file }
mut waited = 0
while not ($port_file | path exists) {
    sleep 50ms
    $waited += 1
    if $waited > 200 {
        job kill $server
        rm --recursive $dir
        error make --unspanned {msg: "stub.py did not come up"}
    }
}
let port = open --raw $port_file | str trim

try {
    with-env {TYPESAFE_URL: $"http://127.0.0.1:($port)", TYPESAFE_TOKEN: test} {
        let models = typesafe list-models
        assert equal ($models.models | get name) [jev-latest]

        # Each answer typed as its question: the record goes as the body, the token as the
        # bearer, and the response is decoded by its schema.
        let request = {
            model: jev-latest
            state: "I was charged twice. Please fix this ASAP."
            questions: {
                billing: {type: noul, instructions: "Is this ticket about billing?"}
                category: {type: choice, instructions: "What is this ticket about?", criteria: {billing: null, technical: null, other: null}}
                urgency: {type: score, instructions: "How urgent is this message?", criteria: ["Can wait" "Needs attention this week" "Needs attention today"]}
            }
        }
        let response = $request | typesafe system-one
        assert equal $response.model jev-latest
        assert equal ($response.answers | columns | sort) [billing category urgency]
        assert equal $response.answers.billing.type noul
        assert equal ($response.answers.billing.noul | describe) float
        assert equal $response.answers.category.choice billing
        assert equal ($response.answers.category.probabilities | columns | sort) [billing other technical]
        assert equal $response.answers.urgency.score 2.0
        assert equal ($response.answers.urgency.legend | get "2") "Needs attention today"
        assert equal ($response.usage | columns) [input_tokens output_tokens]

        # A request the service refuses is an error naming the status; a request the input
        # type refuses, one without `state`, does not reach it.
        let unknown = {model: jev-latest, state: "x", questions: {kind: {type: mystery}}}
        let refused = try { $unknown | typesafe system-one; "" } catch {|err| $err.msg }
        assert ($refused | str contains "422")
    }

    # The credentials: without the token, the service refuses.
    with-env {TYPESAFE_URL: $"http://127.0.0.1:($port)"} {
        hide-env --ignore-errors TYPESAFE_TOKEN
        let refused = try { typesafe list-models; "" } catch {|err| $err.msg }
        assert ($refused | str contains "401")
    }
} catch {|err|
    job kill $server
    rm --recursive $dir
    error make --unspanned {msg: $err.msg}
}
job kill $server
rm --recursive $dir

if ($env.TYPESAFE_API_KEY? | default "" | is-not-empty) {
    with-env {TYPESAFE_TOKEN: $env.TYPESAFE_API_KEY} {
        hide-env --ignore-errors TYPESAFE_URL
        let models = typesafe list-models
        assert (($models.models | length) > 0)
        print $"typesafe: the service lists ($models.models | get name | str join ', ')"
    }
}
