#!/usr/bin/env bash
set -euxo pipefail

for i in stack-6.30.yaml stack.yaml stack-lts-10.0.yaml stack-lts-11.7.yaml
do
  export STACK_YAML=$i
  stack test haskell-indexer-backend-ghc
  stack install
  pushd kythe-verification
  ./test.sh
  popd
done
banner Success!
