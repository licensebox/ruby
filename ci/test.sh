#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruby -Ilib tests/binding_test.rb
gem build licensebox.gemspec
mkdir -p build/gems
gem install --local licensebox-0.3.0.gem --install-dir "$PWD/build/gems" --no-document
GEM_HOME="$PWD/build/gems" GEM_PATH="$PWD/build/gems" ruby -rlicensebox -e 'abort unless Licensebox::VERSION == "0.3.0"; abort unless Licensebox.native_binding("demo").start_with?("m1:")'
