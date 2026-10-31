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
