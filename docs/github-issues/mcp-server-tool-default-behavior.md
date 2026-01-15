# Enhancement: Update calculate-pod-capacity tool description to encourage default behavior

## Repository
`https://github.com/tosin2013/openshift-cluster-health-mcp`

## Labels
`enhancement`, `ux`, `tools`, `lightspeed-integration`

## Summary

The `calculate-pod-capacity` tool description should explicitly instruct the LLM to use sensible defaults and provide immediate results, rather than asking for clarifying questions.

## Current Behavior

When a user asks:
> "How many more pods can I run before hitting resource limits?"

Lightspeed responds with clarifying questions:
> "I can calculate that precisely — I just need a couple details:
> 1. Scope: cluster-wide or specific namespace?
> 2. Pod resource profile: small / medium / large?
> 3. Safety margin (%) to keep free?
> 4. Include trending analysis?"

## Expected Behavior

Lightspeed should use defaults and provide an immediate answer:
> "Capacity Analysis:
> 
> Current Usage:
> - CPU: 68.2% of quota
> - Memory: 74.5% of quota
> 
> Pod Estimates (based on medium profile):
> - Small pods: ~12 more
> - Medium pods: ~6 more
> - Large pods: ~2 more
> 
> Would you like me to recalculate with different parameters?"

## Root Cause

The tool schema has defaults defined, but the **Description** doesn't explicitly guide the LLM to use them:

```go
// Current description (lines 31-36 in calculate_pod_capacity.go)
func (t *CalculatePodCapacityTool) Description() string {
    return "Calculate how many more pods can be deployed in a namespace or cluster based on " +
        "resource quotas, current usage, and pod profiles. Supports small, medium, large, and " +
        "custom pod sizes with configurable safety margins. Useful for capacity planning questions " +
        "like 'How many more pods can I run?' or 'Can I deploy 50 monitoring agents?'"
}
```

The schema has defaults:
- `namespace`: required (but could default to "cluster")
- `pod_profile`: default "medium"
- `safety_margin`: default 15
- `include_trending`: default true

## Proposed Fix

Update the Description to explicitly guide LLM behavior:

```go
func (t *CalculatePodCapacityTool) Description() string {
    return "Calculate how many more pods can be deployed in a namespace or cluster based on " +
        "resource quotas, current usage, and pod profiles. Supports small, medium, large, and " +
        "custom pod sizes with configurable safety margins.\n\n" +
        "USAGE GUIDANCE: When the user asks about capacity without specifying parameters, " +
        "use these defaults and provide an immediate answer:\n" +
        "- namespace: 'cluster' (cluster-wide analysis)\n" +
        "- pod_profile: 'medium'\n" +
        "- safety_margin: 15\n" +
        "- include_trending: true\n\n" +
        "After providing results, offer to recalculate with different parameters if needed.\n\n" +
        "Example questions this tool answers:\n" +
        "- 'How many more pods can I run?'\n" +
        "- 'Can I deploy 50 monitoring agents?'\n" +
        "- 'What's my cluster capacity?'"
}
```

## Alternative: Update InputSchema

Also consider making `namespace` optional with a default of "cluster":

```go
func (t *CalculatePodCapacityTool) InputSchema() map[string]interface{} {
    return map[string]interface{}{
        "type": "object",
        "properties": map[string]interface{}{
            "namespace": map[string]interface{}{
                "type":        "string",
                "description": "Namespace name to analyze. Use 'cluster' for cluster-wide capacity analysis. Default: 'cluster'",
                "default":     "cluster",  // Add default
            },
            // ... rest of properties
        },
        // Remove "required" or make it empty
        "required": []string{},
    }
}
```

## Testing

After the fix, test these queries:
1. "How many more pods can I run?" → Should return immediate cluster-wide analysis
2. "How many pods can fit in namespace X?" → Should analyze specific namespace
3. "Can I deploy 50 small pods?" → Should calculate with small profile

## Impact

- **User Experience**: Faster, more intuitive responses
- **Consistency**: Matches expected behavior documented in blog posts
- **Adoption**: Reduces friction for new users

## Related

- Blog post: `docs/blog/16-end-to-end-self-healing-with-lightspeed.md` (lines 217-246)
- File: `internal/tools/calculate_pod_capacity.go`
