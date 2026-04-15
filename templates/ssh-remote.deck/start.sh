#!/bin/bash
deck title "$SSH_HOST"
deck status --state starting --desc "Connecting to $SSH_HOST"
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "$SSH_HOST"
deck exit
