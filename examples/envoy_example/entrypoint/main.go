// Entrypoint for the Envoy example: validates the environment, renders the
// Envoy config and execs Envoy. It replaces the usual envsubst-in-Bash script,
// because the runtime image has no shell.
package main

import (
	_ "embed"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"text/template"
)

const (
	envoyPath = "/usr/local/bin/envoy"
	adminPort = 9901
)

//go:embed envoy.yaml.tmpl
var configTemplate string

var configTmpl = template.Must(template.New("envoy").Parse(configTemplate))

type config struct {
	ListenPort   int
	UpstreamHost string
	UpstreamPort int
	AdminPort    int
}

var (
	digits    = regexp.MustCompile(`^[0-9]{1,5}$`)
	hostLabel = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)
)

func parsePort(name, value string) (int, error) {
	if !digits.MatchString(value) {
		return 0, fmt.Errorf("%s=%q: not a port number", name, value)
	}
	port, _ := strconv.Atoi(value)
	if port < 1 || port > 65535 {
		return 0, fmt.Errorf("%s=%q: port must be 1-65535", name, value)
	}
	return port, nil
}

// validHost accepts an IP address or an RFC 1123 host name, including an
// absolute one with a trailing dot.
func validHost(host string) bool {
	if net.ParseIP(host) != nil {
		return true
	}
	host = strings.TrimSuffix(host, ".")
	if len(host) > 253 {
		return false
	}
	for _, label := range strings.Split(host, ".") {
		if !hostLabel.MatchString(label) {
			return false
		}
	}
	return true
}

func isLoopback(host string) bool {
	if ip := net.ParseIP(host); ip != nil {
		return ip.IsLoopback()
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	return host == "localhost" || strings.HasSuffix(host, ".localhost")
}

// loadConfig applies defaults to unset or empty variables and checks every
// value, so the template can only ever emit a host name, an IP or a number.
func loadConfig(getenv func(string) string) (config, error) {
	get := func(name, def string) string {
		if v := getenv(name); v != "" {
			return v
		}
		return def
	}
	c := config{AdminPort: adminPort, UpstreamHost: get("UPSTREAM_HOST", "localhost")}
	var errs []error
	var err error
	if c.ListenPort, err = parsePort("LISTEN_PORT", get("LISTEN_PORT", "8080")); err != nil {
		errs = append(errs, err)
	} else if c.ListenPort == adminPort {
		errs = append(errs, fmt.Errorf("LISTEN_PORT=%d: reserved for the Envoy admin listener", adminPort))
	}
	if c.UpstreamPort, err = parsePort("UPSTREAM_PORT", get("UPSTREAM_PORT", "8081")); err != nil {
		errs = append(errs, err)
	}
	if !validHost(c.UpstreamHost) {
		errs = append(errs, fmt.Errorf("UPSTREAM_HOST=%q: not a host name or IP address", c.UpstreamHost))
	} else if c.UpstreamPort == adminPort && isLoopback(c.UpstreamHost) {
		// Would expose the admin API (/quitquitquit, /config_dump) on the public listener.
		errs = append(errs, fmt.Errorf("UPSTREAM_PORT=%d on %s: that is the Envoy admin listener", adminPort, c.UpstreamHost))
	}
	return c, errors.Join(errs...)
}

func render(c config, path string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if err := configTmpl.Execute(f, c); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func main() {
	c, err := loadConfig(os.Getenv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "entrypoint:", err)
		os.Exit(2)
	}
	path := filepath.Join(os.TempDir(), "envoy.yaml")
	if err := render(c, path); err != nil {
		fmt.Fprintln(os.Stderr, "entrypoint: render config:", err)
		os.Exit(1)
	}
	// Hot restart needs a supervisor and shared memory; a container restarts instead.
	args := append([]string{envoyPath, "-c", path, "--disable-hot-restart"}, os.Args[1:]...)
	err = syscall.Exec(envoyPath, args, os.Environ())
	fmt.Fprintln(os.Stderr, "entrypoint: exec envoy:", err)
	os.Exit(1)
}
