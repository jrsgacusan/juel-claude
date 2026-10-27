#!/bin/sh
# juel:yuna's state and checks: yuki.sh's, kept in <git common dir>/yuna (see yuki.sh's header).
exec sh "$(dirname "$0")/../yuki/yuki.sh" --kind yuna "$@"
