#!/usr/bin/env bash

X_PREFIX=$1

if [ -z "$X_PREFIX" ]; then
  echo 'A prefix must be provided';
  exit 1;
fi

terraform import -var-file "$X_PREFIX.terraform.tfvars" -state "$X_PREFIX.terraform.tfstate" "${@:2}"
