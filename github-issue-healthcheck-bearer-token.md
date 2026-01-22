# Enhancement: Add bearer token authentication to healthcheck binary

## Issue Description

The healthcheck binary successfully checks the coordination-engine endpoint, but fails when checking authenticated endpoints like OpenShift Prometheus which requires bearer token authentication.

**Current Status**:
- ✅ Coordination Engine health check: **Working**
- ❌ Prometheus health check: **Timing out** (requires authentication)

**Error Evidence**:
```
Service at http://prometheus-k8s.openshift-monitoring.svc:9090/-/ready not ready:
Get "http://prometheus-k8s.openshift-monitoring.svc:9090/-/ready": context deadline exceeded
(Client.Timeout exceeded while awaiting headers)
```

## Root Cause

OpenShift Prometheus requires bearer token authentication via the `Authorization` header. The current healthcheck binary doesn't support authentication, causing timeouts when trying to access protected endpoints.

**OpenShift Prometheus Configuration**:
- Service: `prometheus-k8s.openshift-monitoring.svc`
- Port: 9091 (requires authentication)
- Port: 9092 (metrics/federate only, internal use)
- Authentication: Bearer token from ServiceAccount mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- TLS: HTTPS with cluster CA

## Current Working Implementation

The coordination-engine health check works perfectly:

```yaml
- name: wait-for-coordination-engine
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  imagePullPolicy: Always
  command: ["/usr/local/bin/healthcheck", "http://coordination-engine:8080/health"]
```

**Log output**:
```
Service at http://coordination-engine:8080/health is ready! (HTTP 200)
```

## Proposed Solution

Enhance the healthcheck binary to support bearer token authentication and TLS verification.

### Implementation

#### 1. Update `cmd/healthcheck/main.go`

Add support for:
- Bearer token authentication (from file or flag)
- Custom HTTP headers
- TLS certificate verification (with optional skip-verify)
- HTTPS endpoints

```go
package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	// Existing flags
	timeout := flag.Duration("timeout", 5*time.Second, "HTTP request timeout")
	interval := flag.Duration("interval", 10*time.Second, "Retry interval between health checks")
	maxRetries := flag.Int("max-retries", 0, "Maximum number of retries (0 = unlimited)")

	// New authentication flags
	bearerTokenFile := flag.String("bearer-token-file", "", "Path to bearer token file (e.g., /var/run/secrets/kubernetes.io/serviceaccount/token)")
	bearerToken := flag.String("bearer-token", "", "Bearer token string (alternative to file)")
	insecureSkipVerify := flag.Bool("insecure-skip-verify", false, "Skip TLS certificate verification (use with caution)")
	header := flag.String("header", "", "Additional header in format 'Name: Value'")

	flag.Parse()

	// Validate args
	args := flag.Args()
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "Usage: healthcheck <url> [options]")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "Options:")
		fmt.Fprintln(os.Stderr, "  --timeout=<duration>              HTTP request timeout (default: 5s)")
		fmt.Fprintln(os.Stderr, "  --interval=<duration>             Retry interval (default: 10s)")
		fmt.Fprintln(os.Stderr, "  --max-retries=<n>                 Maximum retries, 0=unlimited (default: 0)")
		fmt.Fprintln(os.Stderr, "  --bearer-token-file=<path>        Path to bearer token file")
		fmt.Fprintln(os.Stderr, "  --bearer-token=<token>            Bearer token string")
		fmt.Fprintln(os.Stderr, "  --insecure-skip-verify            Skip TLS verification")
		fmt.Fprintln(os.Stderr, "  --header=<name:value>             Custom HTTP header")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "Examples:")
		fmt.Fprintln(os.Stderr, "  # Simple HTTP health check")
		fmt.Fprintln(os.Stderr, "  healthcheck http://coordination-engine:8080/health")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "  # Authenticated Prometheus health check with ServiceAccount token")
		fmt.Fprintln(os.Stderr, "  healthcheck https://prometheus-k8s.openshift-monitoring.svc:9091/-/ready \\")
		fmt.Fprintln(os.Stderr, "    --bearer-token-file=/var/run/secrets/kubernetes.io/serviceaccount/token \\")
		fmt.Fprintln(os.Stderr, "    --insecure-skip-verify")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "  # With custom timeout and interval")
		fmt.Fprintln(os.Stderr, "  healthcheck http://service:8080/healthz --timeout=10s --interval=5s --max-retries=30")
		os.Exit(1)
	}

	url := args[0]

	// Configure HTTP client with TLS settings
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: *insecureSkipVerify,
		},
	}
	client := &http.Client{
		Timeout:   *timeout,
		Transport: transport,
	}

	// Load bearer token if specified
	var token string
	if *bearerTokenFile != "" {
		tokenBytes, err := os.ReadFile(*bearerTokenFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading bearer token file: %v\n", err)
			os.Exit(1)
		}
		token = string(tokenBytes)
	} else if *bearerToken != "" {
		token = *bearerToken
	}

	retries := 0
	for {
		// Create request
		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating request: %v\n", err)
			os.Exit(1)
		}

		// Add bearer token if provided
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}

		// Add custom header if provided
		if *header != "" {
			// Parse header (format: "Name: Value")
			// Simple implementation - could be enhanced
			req.Header.Add("X-Custom-Header", *header)
		}

		// Execute request
		resp, err := client.Do(req)
		if err == nil && resp.StatusCode >= 200 && resp.StatusCode < 300 {
			_ = resp.Body.Close()
			fmt.Printf("Service at %s is ready! (HTTP %d)\n", url, resp.StatusCode)
			os.Exit(0)
		}

		// Log the failure reason
		if err != nil {
			fmt.Printf("Service at %s not ready: %v\n", url, err)
		} else {
			fmt.Printf("Service at %s not ready: HTTP %d\n", url, resp.StatusCode)
			_ = resp.Body.Close()
		}

		retries++
		if *maxRetries > 0 && retries >= *maxRetries {
			fmt.Fprintf(os.Stderr, "Max retries (%d) exceeded, giving up\n", *maxRetries)
			os.Exit(1)
		}

		fmt.Printf("Retrying in %v... (attempt %d", *interval, retries)
		if *maxRetries > 0 {
			fmt.Printf("/%d", *maxRetries)
		}
		fmt.Println(")")
		time.Sleep(*interval)
	}
}
```

#### 2. Update Deployment YAML (Downstream)

Once the enhanced binary is available, update init containers to use authenticated Prometheus endpoint:

```yaml
initContainers:
- name: wait-for-coordination-engine
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  imagePullPolicy: Always
  command: ["/usr/local/bin/healthcheck", "http://coordination-engine:8080/health"]
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
    runAsNonRoot: true

- name: wait-for-prometheus
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  imagePullPolicy: Always
  command:
  - /usr/local/bin/healthcheck
  - https://prometheus-k8s.openshift-monitoring.svc:9091/-/ready
  - --bearer-token-file=/var/run/secrets/kubernetes.io/serviceaccount/token
  - --insecure-skip-verify
  - --timeout=10s
  - --interval=15s
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
    runAsNonRoot: true
```

## Benefits

- ✅ **Unified health check solution** - Single binary handles both authenticated and unauthenticated endpoints
- ✅ **OpenShift compatibility** - Works with ServiceAccount tokens mounted in pods
- ✅ **Flexible authentication** - Supports both file-based and direct token input
- ✅ **TLS support** - Handles HTTPS endpoints with optional verification skip
- ✅ **Production-ready** - Proper error handling and retry logic
- ✅ **Backward compatible** - Existing usage without authentication flags continues to work

## Testing

After implementation, verify both health checks work:

### Test 1: Coordination Engine (No Auth)
```bash
oc logs -n self-healing-platform <mcp-server-pod> -c wait-for-coordination-engine

# Expected output:
# Service at http://coordination-engine:8080/health is ready! (HTTP 200)
```

### Test 2: Prometheus (Authenticated)
```bash
oc logs -n self-healing-platform <mcp-server-pod> -c wait-for-prometheus

# Expected output:
# Service at https://prometheus-k8s.openshift-monitoring.svc:9091/-/ready is ready! (HTTP 200)
```

### Test 3: Manual Testing in Pod
```bash
# Test unauthenticated endpoint
oc exec -n self-healing-platform <pod> -- \
  /usr/local/bin/healthcheck http://coordination-engine:8080/health

# Test authenticated endpoint
oc exec -n self-healing-platform <pod> -- \
  /usr/local/bin/healthcheck \
  https://prometheus-k8s.openshift-monitoring.svc:9091/-/ready \
  --bearer-token-file=/var/run/secrets/kubernetes.io/serviceaccount/token \
  --insecure-skip-verify
```

### Test 4: Verify mcp-server Pods Start Successfully
```bash
oc get pods -n self-healing-platform -l app.kubernetes.io/component=mcp-server

# Expected: All pods Running (1/1)
# NAME                          READY   STATUS    RESTARTS   AGE
# mcp-server-5fb6fd4fc-xxxxx    1/1     Running   0          2m
```

## Security Considerations

### Bearer Token Security
- ✅ Token read from ServiceAccount volume mount (secure)
- ✅ Token never logged or exposed in error messages
- ✅ Token only used for health check requests
- ✅ Follows OpenShift RBAC best practices

### TLS Certificate Verification
- ⚠️ `--insecure-skip-verify` flag should be used carefully
- For OpenShift internal services, cluster CA verification is complex
- Alternative: Mount cluster CA and verify properly (future enhancement)

### Minimal Permissions Required
The ServiceAccount (`self-healing-operator`) only needs:
- Read access to Prometheus `/health` or `/-/ready` endpoints
- No additional RBAC permissions needed beyond existing setup

## Affected Branches

This enhancement should be implemented in **ALL active release branches**:
- `main`
- `release-4.18` (current priority)
- `release-4.19`
- `release-4.20`

## Priority

**High** - Currently blocks mcp-server pods from starting successfully when Prometheus health check is enabled.

## Workaround (Temporary)

Until this enhancement is implemented, the Prometheus init container can be:
1. Removed from the deployment (mcp-server handles Prometheus connectivity at runtime)
2. Changed to check coordination-engine instead (loses Prometheus readiness validation)

## Related Issues

- #53 - Original healthcheck binary implementation
- Related to mcp-server deployment failures in openshift-aiops-platform

## Acceptance Criteria

- [ ] `cmd/healthcheck/main.go` updated with bearer token support
- [ ] `--bearer-token-file` flag implemented
- [ ] `--bearer-token` flag implemented
- [ ] `--insecure-skip-verify` flag implemented
- [ ] TLS/HTTPS endpoint support working
- [ ] Backward compatibility maintained (existing usage without flags works)
- [ ] Changes implemented in all active release branches
- [ ] CI/CD builds successfully with enhanced binary
- [ ] Images pushed to quay.io with enhanced healthcheck
- [ ] Manual testing confirms both auth and non-auth endpoints work
- [ ] Documentation updated with authentication examples

## Additional Enhancements (Optional - Future Work)

1. **Custom Headers Support** - For more complex authentication schemes
2. **Cluster CA Verification** - Proper TLS verification without skip-verify
3. **Multiple Authentication Methods** - OAuth, API keys, etc.
4. **Health Check Response Validation** - Check response body content
5. **Verbose Logging Mode** - Debug flag for troubleshooting
