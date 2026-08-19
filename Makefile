.PHONY: build test check bundle icons icon-check version-check standards-check \
	prepare-formal-release release-check release-tag release-formal verify-artifact \
	publish-release publish-update-mirrors install-release verify-installed refresh-standards

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

version-check:
	python3 scripts/release_tool.py version-check

standards-check:
	STANDARDS_ROOT="$(STANDARDS_ROOT)" bash scripts/standards-check.sh --strict

prepare-formal-release:
	@test -n "$(TARGET_VERSION)" || { echo "TARGET_VERSION is required" >&2; exit 64; }
	@test -n "$(TARGET_BUILD)" || { echo "TARGET_BUILD is required" >&2; exit 64; }
	TARGET_VERSION="$(TARGET_VERSION)" TARGET_BUILD="$(TARGET_BUILD)" \
		STANDARDS_ROOT="$(STANDARDS_ROOT)" bash scripts/prepare-formal-release.sh

release-check:
	@test -n "$(DEVELOPER_ID_APPLICATION)" || { echo "DEVELOPER_ID_APPLICATION is required" >&2; exit 64; }
	DEVELOPER_ID_APPLICATION="$(DEVELOPER_ID_APPLICATION)" \
		STANDARDS_ROOT="$(STANDARDS_ROOT)" bash scripts/release-check.sh

release-tag:
	bash scripts/create-release-tag.sh

release-formal:
	@test -n "$(DEVELOPER_ID_APPLICATION)" || { echo "DEVELOPER_ID_APPLICATION is required" >&2; exit 64; }
	@test -n "$(NOTARY_PROFILE)" || { echo "NOTARY_PROFILE is required" >&2; exit 64; }
	DEVELOPER_ID_APPLICATION="$(DEVELOPER_ID_APPLICATION)" NOTARY_PROFILE="$(NOTARY_PROFILE)" \
		bash scripts/formal-release.sh

verify-artifact:
	@test -n "$(RELEASE_PROVENANCE)" || { echo "RELEASE_PROVENANCE is required" >&2; exit 64; }
	bash scripts/verify-artifact.sh "$(RELEASE_PROVENANCE)"

publish-release:
	@test -n "$(RELEASE_PROVENANCE)" || { echo "RELEASE_PROVENANCE is required" >&2; exit 64; }
	STANDARDS_ROOT="$(STANDARDS_ROOT)" bash scripts/publish-release.sh "$(RELEASE_PROVENANCE)"

publish-update-mirrors:
	@test -n "$(RELEASE_PROVENANCE)" || { echo "RELEASE_PROVENANCE is required" >&2; exit 64; }
	STANDARDS_ROOT="$(STANDARDS_ROOT)" bash scripts/publish-update-mirrors.sh "$(RELEASE_PROVENANCE)"

install-release:
	@test -n "$(RELEASE_PROVENANCE)" || { echo "RELEASE_PROVENANCE is required" >&2; exit 64; }
	bash scripts/install-release.sh "$(RELEASE_PROVENANCE)"

verify-installed:
	@test -n "$(RELEASE_PROVENANCE)" || { echo "RELEASE_PROVENANCE is required" >&2; exit 64; }
	bash scripts/verify-installed.sh "$(RELEASE_PROVENANCE)"

refresh-standards:
	python3 scripts/release_tool.py refresh-standards
