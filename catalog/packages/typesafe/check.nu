#!/usr/bin/env nu
# Lists the models from the service when `TYPESAFE_API_KEY` is set; without a key there is
# nothing to check here. What each wrapper sends is held to the HTTP mapping by the catalog's
# `nus check`, and how a generated wrapper sends and decodes by nusage's own tests.
use std/assert
use typesafe *

if ($env.TYPESAFE_API_KEY? | default "" | is-not-empty) {
    with-env {TYPESAFE_TOKEN: $env.TYPESAFE_API_KEY} {
        hide-env --ignore-errors TYPESAFE_URL
        let models = typesafe list-models
        assert (($models.models | length) > 0)
        print $"typesafe: the service lists ($models.models | get name | str join ', ')"
    }
}
