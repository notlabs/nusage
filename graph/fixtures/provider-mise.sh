#!/bin/sh
for arg do
    case "$arg" in
        //graph/*:provider) provider=$arg ;;
    esac
done
printf '{"kind":"input","path":"%s/z"}\n' "$provider"
printf '{"kind":"input","path":"%s/a"}\n' "$provider"
