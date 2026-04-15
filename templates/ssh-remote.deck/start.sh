#!/bin/bash
# SSH remote session
# Set SSH_HOST in session.toml or pass via environment:
#   [startup]
#   working_dir = "~"
#
# Or edit this script to hardcode your host.

HOST="${SSH_HOST:-}"

if [ -z "$HOST" ]; then
    echo "Enter SSH destination (e.g. user@hostname):"
    read -r HOST
fi

if [ -z "$HOST" ]; then
    echo "No host specified."
    deck exit
    exit 1
fi

deck status --state starting --desc "Connecting to $HOST"
deck title "$HOST"

ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "$HOST"

deck status --state idle --desc "Disconnected"
deck exit
