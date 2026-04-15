#!/bin/bash
deck status --state idle --desc "$(pwd)"
exec "${SHELL:-/bin/zsh}" -l
