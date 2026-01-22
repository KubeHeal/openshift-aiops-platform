# Fix: Replace curl-based health checks with native Go binary

## Issue Description

The mcp-server init containers are currently failing because they use `curl` commands for health checks, but the application image (`quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest`) does not have `curl` installed.

**Current Status**: mcp-server pods stuck in `Init:0/2` state

**Error Evidence**:
```
Error: container init-coordination-engine has failed in pod mcp-server-7df4cbb765-4xqt5
Reason: CrashLoopBackOff
Message: sh: curl: command not found
```

## Root Cause

The mcp-server Deployment YAML uses curl-based init containers:

```yaml
initContainers:
- name: wait-for-coordination-engine
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  command: [sh, -c, "until curl -sf http://coordination-engine:8080/health; do echo 'Waiting...'; sleep 10; done"]
```

The Go-based application image doesn't include curl, causing init container failures.

## Proposed Solution

Create a lightweight Go-based health check binary that can be included in the application image without adding external dependencies.

### Implementation Steps

#### 1. Create Health Check Binary

Create `cmd/healthcheck/main.go`:

```go
package main

import (
    "fmt"
    "net/http"
    "os"
    "time"
)

func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: healthcheck <url>")
        os.Exit(1)
    }

    url := os.Args[1]
    client := &http.Client{Timeout: 5 * time.Second}

    for {
        resp, err := client.Get(url)
        if err == nil && resp.StatusCode == 200 {
            resp.Body.Close()
            fmt.Printf("Service at %s is ready!\n", url)
            os.Exit(0)
        }
        if resp != nil {
            resp.Body.Close()
        }
        fmt.Printf("Service at %s not ready, retrying in 10s...\n", url)
        time.Sleep(10 * time.Second)
    }
}
```

#### 2. Update Dockerfile

Add a multi-stage build to include the health check binary:

```dockerfile
# Build healthcheck binary
FROM golang:1.21 AS healthcheck-builder
WORKDIR /workspace
COPY cmd/healthcheck/main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o healthcheck main.go

# Build main application (existing stage)
FROM golang:1.21 AS builder
WORKDIR /workspace
# ... existing build steps ...

# Final runtime image
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=healthcheck-builder /workspace/healthcheck /usr/local/bin/healthcheck
COPY --from=builder /workspace/mcp-server /usr/local/bin/mcp-server
# ... rest of existing Dockerfile ...
```

#### 3. Update Deployment YAML (Downstream)

The downstream repository (openshift-aiops-platform) will update the deployment to use the new binary:

```yaml
initContainers:
- name: wait-for-coordination-engine
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  command: ["/usr/local/bin/healthcheck", "http://coordination-engine:8080/health"]
- name: wait-for-prometheus
  image: quay.io/takinosh/openshift-cluster-health-mcp:4.18-latest
  command: ["/usr/local/bin/healthcheck", "http://prometheus-k8s.openshift-monitoring.svc:9090/-/ready"]
```

## Benefits

- ✅ **Native Go solution** - No external dependencies
- ✅ **Minimal overhead** - Small statically-compiled binary
- ✅ **Maintainable** - Written in the same language as the main application
- ✅ **Clean architecture** - Application image stays minimal, no unnecessary tools
- ✅ **Consistent** - Works across all environments and architectures

## Testing

After implementation, verify:

```bash
# Check pod status
oc get pods -n self-healing-platform -l app.kubernetes.io/component=mcp-server

# Expected: All pods Running (1/1)

# Check init container logs
oc logs -n self-healing-platform <mcp-server-pod> -c wait-for-coordination-engine

# Expected output:
# Service at http://coordination-engine:8080/health not ready, retrying in 10s...
# Service at http://coordination-engine:8080/health is ready!
```

## Affected Branches

This fix should be implemented in **ALL release branches**:
- `main`
- `4.18-latest`
- `4.17-latest`
- `4.16-latest`
- Any other active release branches

## Priority

**High** - This blocks mcp-server deployment in production environments.

## Related Issues

- Discovered in openshift-aiops-platform during pod troubleshooting
- Similar to coordination-engine Prometheus auth fix in PR #19

## Acceptance Criteria

- [ ] `cmd/healthcheck/main.go` created with health check logic
- [ ] Dockerfile updated to build and include healthcheck binary
- [ ] Binary is statically compiled (CGO_ENABLED=0)
- [ ] Binary is placed in `/usr/local/bin/healthcheck`
- [ ] Changes implemented in all active release branches
- [ ] CI/CD builds successfully with new binary
- [ ] Images pushed to quay.io with healthcheck binary included
- [ ] Manual testing confirms init containers work correctly
