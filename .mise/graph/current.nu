# Whether the project graph this mise process resolved its tasks from is the one on disk: the
# `auto` providers run after `mise run` resolves its tasks, so a run that found them stale
# resolved its tasks from the graph they then replaced.
def main [] {
    let file = ".mise/conf.d/_project-graph.toml"
    let current = if ($file | path exists) { open $file | get -o vars.project_graph | default "" } else { "" }
    if ($env.NUS_LOADED_GRAPH? | default "") != $current {
        error make --unspanned {
            msg: "The project graph changed after this mise process resolved its tasks, so they may miss upstream tasks or inputs. Run the command again, or through `mise exec -- mise run ...`, which prepares the graph before the inner `mise run` reads it."
        }
    }
}
