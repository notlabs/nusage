#!/usr/bin/env nusage
#USAGE name "pack"
#USAGE bin "pack"
#USAGE about "Bundle files"
#USAGE arg "<file>..." help="Files to bundle"
#USAGE flag "-t --tag <tag>" var=#true help="Tag to attach, repeatable"
#USAGE flag "-v --verbose" count=#true help="Log more, repeatable"
#USAGE flag "--format <format>" default="tar" help="Archive format" {
#USAGE   choices "tar" "zip"
#USAGE }

$usage
