package main

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

	cliformatter "github.com/docker/cli/cli/command/formatter"
	composeformatter "github.com/docker/compose/v5/cmd/formatter"
	"github.com/docker/compose/v5/pkg/api"
)

// Keep the fixture tied to the actual custom marshaler, not the API struct's fields.
// This is offline: it renders summaries without creating a client or contacting Docker.
func TestPsFixture(t *testing.T) {
	previous := time.Local
	time.Local = time.UTC
	t.Cleanup(func() { time.Local = previous })
	containers := []api.ContainerSummary{
		{
			ID: strings.Repeat("a", 64), Name: "demo-web-1",
			Names: []string{"/demo-web-1"}, Image: "nginx:alpine",
			Command: "nginx -g daemon off;", Project: "demo", Service: "web",
			Created: 1704067200, State: "running", Status: "Up 1 minute", Health: "healthy",
			Publishers: api.PortPublishers{{URL: "0.0.0.0", TargetPort: 80, PublishedPort: 8080, Protocol: "tcp"}},
			Labels:     map[string]string{api.ContainerEngineLabel: "local"},
			Mounts:     []string{"demo_web_data_long_volume_name"}, Networks: []string{"demo_default"},
			LocalVolumes: 1, SizeRw: 2, SizeRootFs: 1000,
		},
		{
			ID: strings.Repeat("b", 64), Name: "demo-job-1",
			Names: []string{"/demo-job-1"}, Image: "busybox:latest",
			Command: "sh -c exit 7", Project: "demo", Service: "job",
			Created: 1704067200, State: "exited", Status: "Exited (7)", ExitCode: 7,
		},
	}
	var raw bytes.Buffer
	context := cliformatter.Context{
		Output: &raw, Format: composeformatter.NewContainerFormat("json", false, false, false),
		Trunc: false,
	}
	if err := composeformatter.ContainerWrite(context, containers); err != nil {
		t.Fatal(err)
	}
	var normalized bytes.Buffer
	lines := bytes.Split(bytes.TrimSpace(raw.Bytes()), []byte("\n"))
	if len(lines) != len(containers) {
		t.Fatalf("want one JSON object per container, got %d lines", len(lines))
	}
	for _, line := range lines {
		var record map[string]any
		if err := json.Unmarshal(line, &record); err != nil {
			t.Fatal(err)
		}
		// This accessor is relative to time.Now; retain its string type, normalize its value.
		if value, ok := record["RunningFor"].(string); !ok || !strings.HasSuffix(value, " ago") {
			t.Fatalf("unexpected RunningFor: %v", record["RunningFor"])
		}
		record["RunningFor"] = "<elapsed> ago"
		if err := json.NewEncoder(&normalized).Encode(record); err != nil {
			t.Fatal(err)
		}
	}
	expected, err := os.ReadFile("../schemas/fixtures/ps.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(normalized.Bytes(), expected) {
		t.Fatalf("ps formatter fixture differs; actual:\n%s", normalized.Bytes())
	}
	raw.Reset()
	if err := composeformatter.ContainerWrite(context, nil); err != nil {
		t.Fatal(err)
	}
	if raw.Len() != 0 {
		t.Fatalf("empty ps output must have no JSON lines, got %q", raw.String())
	}
}
