#!/bin/sh -e
cask exec ert-runner -L . -L test "$@"
