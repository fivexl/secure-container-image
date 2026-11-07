package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func env(vars map[string]string) func(string) string {
	return func(name string) string { return vars[name] }
}

func TestLoadConfigDefaults(t *testing.T) {
	c, err := loadConfig(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	want := config{ListenPort: 8080, UpstreamHost: "localhost", UpstreamPort: 8081, AdminPort: adminPort}
	if c != want {
		t.Fatalf("got %+v, want %+v", c, want)
	}
}

func TestLoadConfigValid(t *testing.T) {
	for _, host := range []string{"app", "goapp.internal", "10.0.0.7", "fd00::1", "a-b.example.com", "goapp.default.svc.cluster.local."} {
		c, err := loadConfig(env(map[string]string{"LISTEN_PORT": "10000", "UPSTREAM_HOST": host, "UPSTREAM_PORT": "80"}))
		if err != nil {
			t.Errorf("%s: %v", host, err)
			continue
		}
		if c.ListenPort != 10000 || c.UpstreamHost != host || c.UpstreamPort != 80 {
			t.Errorf("%s: got %+v", host, c)
		}
	}
}

func TestLoadConfigInvalid(t *testing.T) {
	cases := map[string]map[string]string{
		"port zero":        {"LISTEN_PORT": "0"},
		"port too large":   {"UPSTREAM_PORT": "65536"},
		"signed port":      {"LISTEN_PORT": "+80"},
		"port with spaces": {"LISTEN_PORT": " 80"},
		"admin port":       {"LISTEN_PORT": "9901"},
		"yaml in host":     {"UPSTREAM_HOST": "x\"}\n  evil: {"},
		"host with port":   {"UPSTREAM_HOST": "app:8080"},
		"leading hyphen":   {"UPSTREAM_HOST": "-app"},
		"empty label":      {"UPSTREAM_HOST": "app..internal"},
		"long label":       {"UPSTREAM_HOST": strings.Repeat("a", 64)},
		"bracketed ipv6":   {"UPSTREAM_HOST": "[::1]"},
		"zone id":          {"UPSTREAM_HOST": "fe80::1%eth0"},
		"only a dot":       {"UPSTREAM_HOST": "."},
		"two dots":         {"UPSTREAM_HOST": "app.."},
		"name too long":    {"UPSTREAM_HOST": strings.Repeat("a.", 127) + "a"},
		"admin default":    {"UPSTREAM_PORT": "9901"},
		"admin loopback":   {"UPSTREAM_HOST": "127.0.0.2", "UPSTREAM_PORT": "9901"},
		"admin ipv6":       {"UPSTREAM_HOST": "::1", "UPSTREAM_PORT": "9901"},
		"admin localhost.": {"UPSTREAM_HOST": "LocalHost.", "UPSTREAM_PORT": "9901"},
	}
	for name, vars := range cases {
		if _, err := loadConfig(env(vars)); err == nil {
			t.Errorf("%s: accepted %v", name, vars)
		}
	}
}

func TestLoadConfigAllowsRemoteAdminPort(t *testing.T) {
	if _, err := loadConfig(env(map[string]string{"UPSTREAM_HOST": "metrics", "UPSTREAM_PORT": "9901"})); err != nil {
		t.Fatal(err)
	}
}

func TestLoadConfigReportsEveryError(t *testing.T) {
	_, err := loadConfig(env(map[string]string{"LISTEN_PORT": "x", "UPSTREAM_PORT": "y", "UPSTREAM_HOST": "z z"}))
	for _, name := range []string{"LISTEN_PORT", "UPSTREAM_PORT", "UPSTREAM_HOST"} {
		if err == nil || !strings.Contains(err.Error(), name) {
			t.Errorf("error does not mention %s: %v", name, err)
		}
	}
}

func TestRender(t *testing.T) {
	path := filepath.Join(t.TempDir(), "envoy.yaml")
	c := config{ListenPort: 8080, UpstreamHost: "goapp", UpstreamPort: 8081, AdminPort: adminPort}
	if err := render(c, path); err != nil {
		t.Fatal(err)
	}
	out, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"address: 127.0.0.1, port_value: 9901",
		"address: 0.0.0.0, port_value: 8080",
		`address: "goapp", port_value: 8081`,
		"dns_lookup_family: V4_PREFERRED",
	} {
		if !strings.Contains(string(out), want) {
			t.Errorf("rendered config lacks %q", want)
		}
	}
}
