.PHONY: build test race vet fmt check integration-large-pr

build:
	go build -trimpath -o bin/gitranger ./cmd/gitranger

test:
	go test ./... -count=1 -timeout=60s

race:
	go test -race ./... -count=1 -timeout=120s

vet:
	go vet ./...

fmt:
	gofmt -w cmd internal

check:
	test -z "$$(gofmt -l cmd internal)"
	go vet ./...
	go test -race ./... -count=1 -timeout=120s
	go build -trimpath ./cmd/gitranger

integration-large-pr:
	test -n "$(GITRANGER_GITHUB_LARGE_PR)"
	go test ./internal/scm -run TestGitHubLargePullRequestReadOnlyIntegration \
		-v -count=1 -timeout=180s
