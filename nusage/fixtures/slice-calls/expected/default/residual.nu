{
    script: (./callee.nu $usage.args.who --loud)
    task: (mise run greet $usage.args.who)
}
