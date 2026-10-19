#!/bin/sh
# The decision library: notes.sh on the library shelf, <HOME>/library/<project>/L-<nnnn>-<slug>.md.
#   library.sh [--home H] --project P add --title T [--decision D --why W --source-text S]
#       [--source owner|brief-worker|worker-note|star|migration] [--since YYYY-MM-DD]
#       [--from <item> [--from-decision D<n>]]              -> added <id> <path>
#   library.sh ... replace <old-id> <add options>           -> added <new-id> <path> replaces <old-id>
#   library.sh ... promote <item>#D<n> [--source ...] [--supersedes <item>#D<m>]
#                                                           -> added <id> <path>[ replaces <old-id>] | exists <id>
#   library.sh ... use <id> <item>                          -> used <id> <item>
#   library.sh ... set <id> status=replaced                 -> set <id>
#   library.sh ... list [--all]                             -> <id>\t<kind>\t<status>\t<always>\t<title>
# Exit: 0; 1 an id or a decision was not found; 2 a file cannot be read or written; 64 usage.
# See notes.sh for the note format and the rules.
exec sh "$(dirname "$0")/notes.sh" --shelf library "$@"
