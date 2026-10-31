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

# Swagger Petstore
#
# A sample API that uses a petstore as an example.
#
# The long story.
@usage 'version "1.0.0"'
export def main []: nothing -> string {
    nus base petstore "https://petstore.example.com/v1"
}

# List all pets
@usage 'flag "--limit" help="How many items to return at one time (max 100)" {
        arg (int)"<LIMIT>"
    }'
@usage 'flag "--status" {
        arg "<STATUS>" {
            choices "available" "sold"
        }
    }'
@usage 'flag "--tags" help="Only pets with these tags" var=#true {
        arg "<TAGS>"
    }'
@usage 'flag "--x-request-id" {
        arg "<X_REQUEST_ID>"
    }'
@usage 'output "json" framing="json" default=#true {
        schema file="schemas/list-pets.schema.json"
    }'
export def "petstore list-pets" [
    --limit: int,                       # How many items to return at one time (max 100)
    --status: string@[available sold],
    --tags: list<string>,               # Only pets with these tags
    --x-request-id: string,
]: nothing -> table<name: string, tag: oneof<string, nothing>, owner: oneof<record<name: string, pets: oneof<int, nothing>>, nothing>, born: oneof<datetime, nothing>, id: int> {
    let text = nus request {
        service: petstore
        base: "https://petstore.example.com/v1"
        auth: [{kind: bearer}]
        method: get
        path: /pets
        params: {}
        query: {limit: $limit, status: $status, tags: $tags}
        headers: {X-Request-Id: $x_request_id}
    }
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"Pet\":{\"allOf\":[{\"$ref\":\"#/$defs/NewPet\"},{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"integer\",\"format\":\"int64\"}}}]},\"NewPet\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"tag\":{\"type\":[\"string\",\"null\"]},\"owner\":{\"anyOf\":[{\"$ref\":\"#/$defs/Owner\"},{\"type\":\"null\"}]},\"born\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"Owner\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"pets\":{\"type\":\"integer\",\"exclusiveMinimum\":0}}}},\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/Pet\"}}" { from json | default null tag | default null owner | update owner {|row| if $row.owner == null { null } else { $row.owner | default null pets } } | default null born | update born {|row| if $row.born == null { null } else { $row.born | into datetime } } }
}

# Create a pet
@usage 'output "json" framing="json" default=#true {
        schema file="schemas/create-pets.schema.json"
    }'
export def "petstore create-pets" []: record<name: string> -> record<name: string, tag: oneof<string, nothing>, owner: oneof<record<name: string, pets: oneof<int, nothing>>, nothing>, born: oneof<datetime, nothing>, id: int> {
    let body = $in
    let text = nus request {
        service: petstore
        base: "https://petstore.example.com/v1"
        auth: [{kind: bearer}]
        method: post
        path: /pets
        params: {}
        query: {}
        headers: {}
        body: $body
        media: application/json
    }
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"Pet\":{\"allOf\":[{\"$ref\":\"#/$defs/NewPet\"},{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"integer\",\"format\":\"int64\"}}}]},\"NewPet\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"tag\":{\"type\":[\"string\",\"null\"]},\"owner\":{\"anyOf\":[{\"$ref\":\"#/$defs/Owner\"},{\"type\":\"null\"}]},\"born\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"Owner\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"pets\":{\"type\":\"integer\",\"exclusiveMinimum\":0}}}},\"$ref\":\"#/$defs/Pet\"}" { from json | default null tag | default null owner | update owner {|row| if $row.owner == null { null } else { $row.owner | default null pets } } | default null born | update born {|row| if $row.born == null { null } else { $row.born | into datetime } } }
}

# Info for a specific pet
@usage 'arg (int)"<pet-id>" help="The id of the pet"'
@usage 'output "json" framing="json" default=#true {
        schema file="schemas/show-pet-by-id.schema.json"
    }'
export def "petstore show-pet-by-id" [
    pet_id: int,  # The id of the pet
]: nothing -> record<name: string, tag: oneof<string, nothing>, owner: oneof<record<name: string, pets: oneof<int, nothing>>, nothing>, born: oneof<datetime, nothing>, id: int> {
    let text = nus request {
        service: petstore
        base: "https://petstore.example.com/v1"
        auth: [{kind: bearer}]
        method: get
        path: "/pets/{petId}"
        params: {petId: $pet_id}
        query: {}
        headers: {}
    }
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"Pet\":{\"allOf\":[{\"$ref\":\"#/$defs/NewPet\"},{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"integer\",\"format\":\"int64\"}}}]},\"NewPet\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"tag\":{\"type\":[\"string\",\"null\"]},\"owner\":{\"anyOf\":[{\"$ref\":\"#/$defs/Owner\"},{\"type\":\"null\"}]},\"born\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"Owner\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"pets\":{\"type\":\"integer\",\"exclusiveMinimum\":0}}}},\"$ref\":\"#/$defs/Pet\"}" { from json | default null tag | default null owner | update owner {|row| if $row.owner == null { null } else { $row.owner | default null pets } } | default null born | update born {|row| if $row.born == null { null } else { $row.born | into datetime } } }
}

# Remove a pet.
@usage 'flag "--force" required=#true'
@usage 'arg (int)"<pet-id>" help="The id of the pet"'
export def "petstore delete-pets-pet-id" [
    pet_id: int,  # The id of the pet
    --force,
]: nothing -> string {
    nus request {
        service: petstore
        base: "https://petstore.example.com/v1"
        auth: [{kind: bearer}]
        method: delete
        path: "/pets/{petId}"
        params: {petId: $pet_id}
        query: {force: $force}
        headers: {}
    }
}
