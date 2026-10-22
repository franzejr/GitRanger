.PHONY: build test race vet fmt check

build:
	go build -trimpath -o bin/gitranger ./cmd/gitranger

test:
	go test ./... -count=1

race:
	go test -race ./... -count=1

vet:
	go vet ./...

fmt:
	gofmt -w cmd internal

check:
	test -z "$$(gofmt -l cmd internal)"
	go vet ./...
	go test -race ./... -count=1
	go build -trimpath ./cmd/gitranger
