.PHONY: build test check bundle icons icon-check

build:
	swift build

test:
	swift test

check:
	bash scripts/compile-check.sh

bundle:
	bash scripts/bundle.sh --debug

icons:
	bash scripts/generate-icon.sh

icon-check:
	bash scripts/generate-icon.sh --check
