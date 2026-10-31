alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nus word" []: any -> string {
    if ($in | describe --detailed | get type) == datetime {
        $in | format date "%+"
    } else {
        $in | into string
    }
}

# The argv for a wrapper's parameters: positionals in order, absent ones dropped, each
# preceded by the clause-scoped flags, then the other flags. A flag goes by its value: a
# switch once when on, a count that many times, a list once per item with its value, any
# other value once with its value; null and false add nothing.
def "nus argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nus flag-words
    let words = $positionals | compact | each { nus word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nus flag-words)
}

def "nus flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nus word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nus word)]
        }
    } | flatten
}

# Where the service is: `$env.<SERVICE>_URL` when set, else the base the mapping names, with
# no `/` at the end; `<SERVICE>` is the service's name in upper case, `-` as `_`.
def "nus base" [service: string, base]: nothing -> string {
    let prefix = $service | str uppercase | str replace --all "-" "_"
    let base = $env | get --optional $"($prefix)_URL" | default $base
    if $base == null {
        error make --unspanned {
            msg: $"the mapping names no base URL for ($service); set $env.($prefix)_URL"
        }
    }
    $base | str trim --right --char "/"
}

# A record's fields that have a value, each as a query or header carries it: a list as a
# list of words, anything else as one word. A null is no value, and so is `false`, a switch
# the call left off.
def "nus given" []: record -> record {
    $in | transpose name value | where value != null and value != false | reduce --fold {} {|field, given|
        let value = if ($field.value | describe --detailed | get type) == list {
            $field.value | each { nus word }
        } else {
            $field.value | nus word
        }
        $given | insert $field.name $value
    }
}

# The request a wrapper makes, and the response's text. The URL is the service's base, as
# `nus base` finds it, the path with each `{param}` filled in, and the query after it, a
# null dropped and a list repeated. The credentials are the environment's: `$env.<SERVICE>_TOKEN`
# is the bearer token, or the key the service asks for in a header or the query, and
# `$env.<SERVICE>_USER` with `$env.<SERVICE>_PASSWORD` is basic authentication; a credential
# the environment lacks is not sent. A body goes as `http post` sends a value of its media
# type: a record as JSON for `application/json`. A response that is not a success is an
# error naming the status, with the response's text.
def "nus request" [request: record]: nothing -> string {
    let prefix = $request.service | str uppercase | str replace --all "-" "_"
    let base = nus base $request.service $request.base
    let path = $request.params | transpose name value | reduce --fold $request.path {|param, path|
        $path | str replace --all $"{($param.name)}" ($param.value | nus word | url encode)
    }
    let token = $env | get --optional $"($prefix)_TOKEN"
    let user = $env | get --optional $"($prefix)_USER"
    let credentials = $request.auth | reduce --fold {headers: {}, query: {}} {|auth, carried|
        match $auth.kind {
            "bearer" if $token != null => {
                $carried | update headers { insert Authorization $"Bearer ($token)" }
            }
            "header" if $token != null => {
                $carried | update headers { insert $auth.name $token }
            }
            "query" if $token != null => {
                $carried | update query { insert $auth.name $token }
            }
            "basic" if $user != null => {
                let password = $env | get --optional $"($prefix)_PASSWORD" | default ""
                let encoded = $"($user):($password)" | encode base64
                $carried | update headers { insert Authorization $"Basic ($encoded)" }
            }
            _ => $carried
        }
    }
    let headers = ($request.headers | nus given) | merge $credentials.headers
    let query = ($request.query | nus given) | merge $credentials.query
    let url = if ($query | is-empty) {
        $"($base)($path)"
    } else {
        $"($base)($path)?($query | url build-query)"
    }
    let body = $request.body? | default null
    let response = if $body == null {
        match $request.method {
            "get" => (http get --full --allow-errors --raw --headers $headers $url)
            "delete" => (http delete --full --allow-errors --raw --headers $headers $url)
            "post" => (http post --full --allow-errors --raw --headers $headers $url "")
            "put" => (http put --full --allow-errors --raw --headers $headers $url "")
            "patch" => (http patch --full --allow-errors --raw --headers $headers $url "")
            _ => (nus unsent $request.method)
        }
    } else {
        let data = $body
        let media = $request.media
        match $request.method {
            "delete" => (
                http delete --full --allow-errors --raw --headers $headers --content-type $media --data $data $url
            )
            "post" => (
                http post --full --allow-errors --raw --headers $headers --content-type $media $url $data
            )
            "put" => (
                http put --full --allow-errors --raw --headers $headers --content-type $media $url $data
            )
            "patch" => (
                http patch --full --allow-errors --raw --headers $headers --content-type $media $url $data
            )
            _ => (nus unsent $request.method)
        }
    }
    if $response.status >= 400 {
        error make --unspanned {
            msg: $"($request.method | str uppercase) ($url) answered ($response.status)\n($response.body)"
        }
    }
    $response.body
}

def "nus unsent" [method: string]: nothing -> error {
    error make --unspanned {msg: $"the wrapper sends no ($method | str uppercase) request"}
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nus` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nus` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nus decoded" [
    text: string
    schema: string
    decode: closure
    --lines
]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let flags = if $lines { [--lines] } else { [] }
        let checked = $text | ^nus validate $file - ...$flags | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                $err | error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                $err | error make --unspanned {
                    msg: $"the output could not be held to its schema: nus validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}

# TypeSafe AI
#
# A System One model answers named questions about a piece of content, the `state`, and
# returns one typed answer per question rather than text: a yes/no probability (`noul`), a
# selection among named choices with their probabilities (`choice`), an expected score
# against an ordered rubric (`score`), or a located box in an image (`box`). The first System
# One model is Jev, reached as `jev-latest`; `jev-preview` answers `box` questions.
#
# Authenticate with an API key as a bearer token. Requests are JSON; the request body may be
# sent compressed with `Content-Encoding: zstd`. An unsuccessful response carries its reason
# in a JSON body, as `error`, `message` or `detail`, and every response carries
# `x-typesafe-request-id`. A rate-limited response says how long to wait in `retry-after`
# or `retry-after-ms`.
@usage 'version "1"'
export def main []: nothing -> string {
    nus base typesafe "https://api.typesafe.ai"
}

# List the models available to the account
@usage 'output "json" framing="json" default=#true {
        schema file="schemas/list-models.schema.json"
    }'
export def "typesafe list-models" []: nothing -> record<models: table<name: string, description: string, release_date: string>> {
    let text = nus request {
        service: typesafe
        base: "https://api.typesafe.ai"
        auth: [{kind: bearer}]
        method: get
        path: "/v1/models"
        params: {}
        query: {}
        headers: {}
    }
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"ModelMetadataList\":{\"type\":\"object\",\"title\":\"ModelMetadataList\",\"required\":[\"models\"],\"properties\":{\"models\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/ModelMetadata\"},\"description\":\"Available models and aliases. Use a model's name in POST /v1/systemone requests.\",\"title\":\"Models\"}}},\"ModelMetadata\":{\"type\":\"object\",\"title\":\"ModelMetadata\",\"required\":[\"name\",\"description\",\"release_date\"],\"properties\":{\"name\":{\"type\":\"string\",\"description\":\"Model name or alias accepted by the request's model field.\",\"title\":\"Name\"},\"description\":{\"type\":\"string\",\"description\":\"Human-readable description of the model and its capabilities.\",\"title\":\"Description\"},\"release_date\":{\"type\":\"string\",\"description\":\"Model release date, formatted as YYYY-MM-DD.\",\"title\":\"Release Date\"}}}},\"$ref\":\"#/$defs/ModelMetadataList\"}" { from json }
}

# Answer named questions about content
@usage 'flag "--type-safe-danger-zone-images" help="Opt in to image assets, which are experimental: `true` to send PNG or JPEG images in `assets`, as base64 data or multipart parts."'
@usage 'output "json" framing="json" default=#true {
        schema file="schemas/system-one.schema.json"
    }'
export def "typesafe system-one" [
    --type-safe-danger-zone-images,  # Opt in to image assets, which are experimental: `true` to send PNG or JPEG images in `assets`, as base64 data or multipart parts.
]: record<model: string, state: oneof<string, record, list<any>>, questions: record> -> record<model: string, answers: record, usage: record<input_tokens: int, output_tokens: int>> {
    let body = $in
    let text = nus request {
        service: typesafe
        base: "https://api.typesafe.ai"
        auth: [{kind: bearer}]
        method: post
        path: "/v1/systemone"
        params: {}
        query: {}
        headers: {TypeSafe-Danger-Zone-Images: $type_safe_danger_zone_images}
        body: $body
        media: application/json
    }
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"SystemOneResponse\":{\"type\":\"object\",\"title\":\"SystemOneResponse\",\"required\":[\"model\",\"answers\",\"usage\"],\"properties\":{\"model\":{\"type\":\"string\",\"description\":\"Name of the model that answered the questions. May differ from the alias supplied in the request.\",\"title\":\"Model\"},\"answers\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#/$defs/Answer\"},\"minProperties\":1,\"description\":\"Answers keyed by the question names supplied in the request. Each answer's type matches its question's type.\",\"title\":\"Answers\"},\"usage\":{\"$ref\":\"#/$defs/Usage\",\"description\":\"Input and output token counts for this evaluation.\"}}},\"Usage\":{\"type\":\"object\",\"title\":\"Usage\",\"required\":[\"input_tokens\",\"output_tokens\"],\"properties\":{\"input_tokens\":{\"type\":\"integer\",\"description\":\"Number of billable input tokens used to evaluate the request.\",\"title\":\"Input Tokens\"},\"output_tokens\":{\"type\":\"integer\",\"description\":\"Number of output tokens used to answer the questions. Output tokens are currently free of charge.\",\"title\":\"Output Tokens\"}}},\"Answer\":{\"description\":\"An answer whose type matches the corresponding question.\",\"oneOf\":[{\"$ref\":\"#/$defs/NoulAnswer\"},{\"$ref\":\"#/$defs/ChoiceAnswer\"},{\"$ref\":\"#/$defs/ScoreAnswer\"},{\"$ref\":\"#/$defs/BoxAnswer\"}],\"discriminator\":{\"propertyName\":\"type\"}},\"BoxAnswer\":{\"type\":\"object\",\"title\":\"BoxAnswer\",\"required\":[\"type\",\"box\",\"confidence\"],\"properties\":{\"type\":{\"type\":\"string\",\"const\":\"box\",\"description\":\"Identifies a box answer.\",\"title\":\"Type\"},\"box\":{\"$ref\":\"#/$defs/BoxCoordinates\",\"description\":\"The box's edges as fractions of image height and width, from 0 to 1. Each coordinate is the expected value of its edge's predicted position.\"},\"confidence\":{\"type\":[\"number\",\"null\"],\"description\":\"Confidence for the given box, from 0 to 1, with 1 being more confident. Null when the model does not provide confidence.\",\"title\":\"Confidence\"}}},\"BoxCoordinates\":{\"type\":\"object\",\"title\":\"BoxCoordinates\",\"required\":[\"top\",\"bottom\",\"left\",\"right\"],\"properties\":{\"top\":{\"type\":\"number\",\"description\":\"Top edge of the box, as a fraction of image height from the top (0-1).\",\"title\":\"Top\"},\"bottom\":{\"type\":\"number\",\"description\":\"Bottom edge of the box, as a fraction of image height from the top (0-1).\",\"title\":\"Bottom\"},\"left\":{\"type\":\"number\",\"description\":\"Left edge of the box, as a fraction of image width from the left (0-1).\",\"title\":\"Left\"},\"right\":{\"type\":\"number\",\"description\":\"Right edge of the box, as a fraction of image width from the left (0-1).\",\"title\":\"Right\"}}},\"ScoreAnswer\":{\"type\":\"object\",\"title\":\"ScoreAnswer\",\"required\":[\"type\",\"score\",\"confidence\",\"legend\",\"probabilities\"],\"properties\":{\"type\":{\"type\":\"string\",\"const\":\"score\",\"description\":\"Identifies a rating against the requested score levels.\",\"title\":\"Type\"},\"score\":{\"type\":\"number\",\"description\":\"Expected score: the probability-weighted average of the rubric levels. May fall between integer levels.\",\"title\":\"Score\"},\"confidence\":{\"type\":\"number\",\"description\":\"Confidence in the score, from 0 to 1. Higher values indicate greater certainty; use lower values to flag uncertain ratings for review.\",\"title\":\"Confidence\"},\"legend\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#/$defs/Content\"},\"description\":\"The requested criteria mapped to their score levels, so you can interpret the score.\",\"title\":\"Legend\"},\"probabilities\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"number\"},\"description\":\"Probability of each score level, from 0 to 1, using the same keys as legend. Shows how likely the alternatives are; values sum to approximately 1.\",\"title\":\"Probabilities\"}}},\"Content\":{\"description\":\"Text, a JSON object or a JSON array; a string may hold an asset's reference.\",\"anyOf\":[{\"type\":\"string\"},{\"type\":\"object\"},{\"type\":\"array\"}]},\"ChoiceAnswer\":{\"type\":\"object\",\"title\":\"ChoiceAnswer\",\"required\":[\"type\",\"choice\",\"confidence\",\"probabilities\"],\"properties\":{\"type\":{\"type\":\"string\",\"const\":\"choice\",\"description\":\"Identifies a selection from the requested choices.\",\"title\":\"Type\"},\"choice\":{\"type\":\"string\",\"description\":\"The name of the choice with the highest probability among the question's criteria.\",\"title\":\"Choice\"},\"confidence\":{\"type\":\"number\",\"description\":\"Confidence in the selected choice, from 0 to 1. Higher values indicate greater certainty; use lower values to flag uncertain selections for review.\",\"title\":\"Confidence\"},\"probabilities\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"number\"},\"description\":\"Probability of each choice in criteria, keyed by choice name, from 0 to 1. Shows how likely the alternatives are; values sum to approximately 1.\",\"title\":\"Probabilities\"}}},\"NoulAnswer\":{\"type\":\"object\",\"title\":\"NoulAnswer\",\"required\":[\"type\",\"noul\"],\"properties\":{\"type\":{\"type\":\"string\",\"const\":\"noul\",\"description\":\"Identifies a yes/no answer.\",\"title\":\"Type\"},\"noul\":{\"type\":\"number\",\"description\":\"Probability of a yes answer or a true statement, from 0 to 1. Values near 1 favor yes or true, values near 0 favor no or false, and values near 0.5 indicate uncertainty.\",\"title\":\"Noul\"}}}},\"$ref\":\"#/$defs/SystemOneResponse\"}" { from json }
}
