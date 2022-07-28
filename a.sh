#!/usr/bin/env bash

X_PREFIX=$1

if [ -z "$X_PREFIX" ]; then
  echo 'A prefix must be provided';
  exit 1;
fi

terraform apply -state "$X_PREFIX.terraform.tfstate" "$X_PREFIX.tfplan"
