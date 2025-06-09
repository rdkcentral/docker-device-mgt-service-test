#!/bin/bash

# Check if correct arguments are given
if [[ "$1" == "jx" && "$2" == "numwqikrlowy" ]]; then
  cat <<EOF
96.118.159.156
96.118.159.245
96.118.159.252
96.118.213.116
2001:558:fc0a:6:f816:3eff:fe19:9cc8
2001:558:fc0a:6:f816:3eff:fe38:224b
2001:558:fc0a:6:f816:3eff:feb2:22bd
EOF
else
  echo "mocked-default-output"
fi
