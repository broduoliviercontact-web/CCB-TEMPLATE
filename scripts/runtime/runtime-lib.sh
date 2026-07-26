#!/bin/sh
runtime_model_is_safe() { case "$1" in ''|*[!A-Za-z0-9._:/-]*) return 1;; *) return 0;; esac; }
runtime_warn() { printf '%s\n' "[WARN] $1" >&2; }
