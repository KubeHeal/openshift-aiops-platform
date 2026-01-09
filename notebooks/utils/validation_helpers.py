"""
Platform Validation Helpers for Self-Healing Platform

This module provides comprehensive infrastructure validation functions for verifying
that all platform components are operational and accessible before users execute
notebooks.

References:
- ADR-029: Infrastructure Validation Notebook for User Readiness
- ADR-012: Notebook Architecture for End-to-End Workflows

Usage:
    from utils.validation_helpers import (
        validate_coordination_engine,
        validate_model_serving,
        validate_object_storage,
        generate_validation_report
    )

    checks = []
    checks.append(validate_coordination_engine())
    checks.append(validate_model_serving())
    report = generate_validation_report(checks)
"""

import requests
import os
import json
import subprocess
from typing import Dict, Any, List, Tuple, Optional
from datetime import datetime
import time

# Optional imports - will be available in RHODS workbench
try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False
    ClientError = Exception
    NoCredentialsError = Exception

# Constants
COORDINATION_ENGINE_URL = "http://coordination-engine:8080"
MCP_SERVER_URL = "http://cluster-health-mcp-server.self-healing-platform.svc.cluster.local:3000"
PROMETHEUS_URL = "https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091"
THANOS_URL = "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091"

# Validation Categories
CATEGORY_BASIC = "Basic Environment"
CATEGORY_PLATFORM = "Platform Infrastructure"
CATEGORY_OPENSHIFT = "OpenShift Components"
CATEGORY_NETWORK = "Network Connectivity"


def _create_check_result(
    category: str,
    component: str,
    check_name: str,
    status: str,
    details: str,
    url: Optional[str] = None,
    response_time_ms: Optional[int] = None,
    remediation: Optional[str] = None
) -> Dict[str, Any]:
    """Create standardized check result dictionary"""
    result = {
        "category": category,
        "component": component,
        "check": check_name,
        "status": status,
        "details": details,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
    if url:
        result["url"] = url
    if response_time_ms is not None:
        result["response_time_ms"] = response_time_ms
    if remediation:
        result["remediation"] = remediation
    return result


def _get_sa_token() -> Optional[str]:
    """
    Get the ServiceAccount token from the mounted secret.
    In OpenShift pods, the SA token is mounted at /var/run/secrets/kubernetes.io/serviceaccount/token
    """
    token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
    try:
        if os.path.exists(token_path):
            with open(token_path, 'r') as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _http_get_with_retry(url: str, timeout: int = 5, retries: int = 3, verify: bool = False, use_sa_token: bool = False) -> Tuple[bool, int, str, int]:
    """
    Perform HTTP GET with retries

    Args:
        url: URL to request
        timeout: Request timeout in seconds
        retries: Number of retries
        verify: Whether to verify SSL certificates
        use_sa_token: Whether to use ServiceAccount token for authentication

    Returns:
        (success, status_code, details, response_time_ms)
    """
    headers = {}
    if use_sa_token:
        token = _get_sa_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"

    for attempt in range(retries):
        try:
            start_time = time.time()
            response = requests.get(url, timeout=timeout, verify=verify, headers=headers)
            elapsed_ms = int((time.time() - start_time) * 1000)
            return (True, response.status_code, f"HTTP {response.status_code}", elapsed_ms)
        except requests.exceptions.Timeout:
            if attempt == retries - 1:
                return (False, 0, "Timeout after 3 retries", 0)
            time.sleep(1)
        except requests.exceptions.ConnectionError as e:
            if attempt == retries - 1:
                return (False, 0, f"Connection error: {str(e)[:100]}", 0)
            time.sleep(1)
        except Exception as e:
            if attempt == retries - 1:
                return (False, 0, f"Error: {str(e)[:100]}", 0)
            time.sleep(1)
    return (False, 0, "Unknown error", 0)


def _run_oc_command(command: List[str]) -> Tuple[bool, str]:
    """
    Run oc command and return (success, output)
    """
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30
        )
        return (result.returncode == 0, result.stdout.strip())
    except subprocess.TimeoutExpired:
        return (False, "Command timed out")
    except Exception as e:
        return (False, str(e))


# =============================================================================
# BASIC ENVIRONMENT VALIDATION
# =============================================================================

def validate_python_version() -> Dict[str, Any]:
    """Validate Python version (3.11+)"""
    import sys
    version = sys.version_info
    passed = version.major == 3 and version.minor >= 11

    return _create_check_result(
        category=CATEGORY_BASIC,
        component="Python",
        check_name="Python Version",
        status="PASSED" if passed else "FAILED",
        details=f"Python {version.major}.{version.minor}.{version.micro}",
        remediation="Install Python 3.11+ in workbench" if not passed else None
    )


def validate_pytorch_installation() -> Dict[str, Any]:
    """Validate PyTorch installation"""
    try:
        import torch
        version = torch.__version__
        passed = True
        return _create_check_result(
            category=CATEGORY_BASIC,
            component="PyTorch",
            check_name="PyTorch Installation",
            status="PASSED",
            details=f"PyTorch {version}"
        )
    except ImportError:
        return _create_check_result(
            category=CATEGORY_BASIC,
            component="PyTorch",
            check_name="PyTorch Installation",
            status="FAILED",
            details="PyTorch not installed",
            remediation="Install PyTorch: pip install torch"
        )


def validate_gpu_availability() -> Dict[str, Any]:
    """Validate GPU availability (WARNING if not available, not blocking)"""
    try:
        import torch
        if torch.cuda.is_available():
            device_count = torch.cuda.device_count()
            device_name = torch.cuda.get_device_name(0) if device_count > 0 else "Unknown"
            return _create_check_result(
                category=CATEGORY_BASIC,
                component="GPU",
                check_name="GPU Availability",
                status="PASSED",
                details=f"{device_count} GPU(s) available: {device_name}"
            )
        else:
            return _create_check_result(
                category=CATEGORY_BASIC,
                component="GPU",
                check_name="GPU Availability",
                status="WARNING",
                details="GPU not available, will use CPU (acceptable for most notebooks)",
                remediation="Most notebooks work on CPU; Phase 02 LSTM notebook requires GPU"
            )
    except Exception as e:
        return _create_check_result(
            category=CATEGORY_BASIC,
            component="GPU",
            check_name="GPU Availability",
            status="WARNING",
            details=f"Could not check GPU: {str(e)}"
        )


def validate_storage_volumes() -> List[Dict[str, Any]]:
    """Validate persistent storage volumes"""
    checks = []

    # Detect if running in validation pod vs workbench
    # Validation pods run in /workspace/repo, workbench runs in /opt/app-root/src
    is_validation_pod = os.path.exists("/workspace/repo")

    # Data volume
    data_path = "/opt/app-root/src/data"
    if os.path.exists(data_path) and os.access(data_path, os.W_OK):
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Data Volume",
            status="PASSED",
            details=f"Mounted at {data_path} (writable)"
        ))
    else:
        # In validation pods, this is expected since PVCs aren't mounted
        status = "WARNING" if is_validation_pod else "FAILED"
        details = f"Not found (validation pod - PVC not mounted)" if is_validation_pod else f"Not found or not writable: {data_path}"
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Data Volume",
            status=status,
            details=details,
            remediation="PVC 'workbench-data' is mounted in workbench, not in validation pods" if is_validation_pod else "Ensure PVC 'workbench-data' is mounted"
        ))

    # Models volume
    models_path = "/opt/app-root/src/models"
    if os.path.exists(models_path) and os.access(models_path, os.W_OK):
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Models Volume",
            status="PASSED",
            details=f"Mounted at {models_path} (writable)"
        ))
    else:
        # In validation pods, this is expected since PVCs aren't mounted
        status = "WARNING" if is_validation_pod else "FAILED"
        details = f"Not found (validation pod - PVC not mounted)" if is_validation_pod else f"Not found or not writable: {models_path}"
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Models Volume",
            status=status,
            details=details,
            remediation="PVC 'model-artifacts' is mounted in workbench, not in validation pods" if is_validation_pod else "Ensure PVC 'model-artifacts' is mounted"
        ))

    # Config directory
    config_path = "/opt/app-root/src/.config"
    os.makedirs(config_path, exist_ok=True)
    if os.access(config_path, os.W_OK):
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Config Directory",
            status="PASSED",
            details=f"Created/verified at {config_path}"
        ))
    else:
        checks.append(_create_check_result(
            category=CATEGORY_BASIC,
            component="Storage",
            check_name="Config Directory",
            status="FAILED",
            details=f"Not writable: {config_path}",
            remediation="Check filesystem permissions"
        ))

    return checks


# =============================================================================
# PLATFORM INFRASTRUCTURE VALIDATION
# =============================================================================

def validate_coordination_engine() -> Dict[str, Any]:
    """Validate coordination engine health and accessibility"""
    url = f"{COORDINATION_ENGINE_URL}/health"
    success, status_code, details, elapsed_ms = _http_get_with_retry(url)

    if success and status_code == 200:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Coordination Engine",
            check_name="Health Endpoint",
            status="PASSED",
            details=details,
            url=url,
            response_time_ms=elapsed_ms
        )
    else:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Coordination Engine",
            check_name="Health Endpoint",
            status="FAILED",
            details=details,
            url=url,
            remediation="Verify coordination engine deployment: oc get deployment coordination-engine -n self-healing-platform"
        )


def validate_coordination_engine_metrics() -> Dict[str, Any]:
    """Validate coordination engine metrics endpoint"""
    url = f"{COORDINATION_ENGINE_URL}/metrics"
    success, status_code, details, elapsed_ms = _http_get_with_retry(url)

    if success and status_code == 200:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Coordination Engine",
            check_name="Metrics Endpoint",
            status="PASSED",
            details=details,
            url=url,
            response_time_ms=elapsed_ms
        )
    else:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Coordination Engine",
            check_name="Metrics Endpoint",
            status="WARNING",
            details=details,
            url=url,
            remediation="Metrics may not be critical for notebook execution"
        )


def validate_coordination_engine_kserve_proxy() -> Dict[str, Any]:
    """
    Validate coordination engine KServe proxy is working.

    Tests /api/v1/models endpoint to verify:
    1. KServe integration is enabled
    2. Coordination engine can proxy to KServe InferenceServices
    3. At least one model is registered

    Returns:
        Check result dictionary with status and details
    """
    url = f"{COORDINATION_ENGINE_URL}/api/v1/models"
    success, status_code, details, elapsed_ms = _http_get_with_retry(url)

    if success and status_code == 200:
        try:
            # Parse JSON response to check for models
            import json
            response_data = json.loads(details)
            models = response_data.get('models', [])
            model_count = len(models)

            if model_count > 0:
                return _create_check_result(
                    category=CATEGORY_PLATFORM,
                    component="Coordination Engine",
                    check_name="KServe Proxy",
                    status="PASSED",
                    details=f"KServe proxy accessible - {model_count} model(s) registered: {', '.join(models)}",
                    url=url,
                    response_time_ms=elapsed_ms
                )
            else:
                return _create_check_result(
                    category=CATEGORY_PLATFORM,
                    component="Coordination Engine",
                    check_name="KServe Proxy",
                    status="WARNING",
                    details="KServe proxy accessible but no models registered",
                    url=url,
                    response_time_ms=elapsed_ms,
                    remediation="Deploy KServe InferenceServices and register in values-hub.yaml"
                )
        except Exception as e:
            return _create_check_result(
                category=CATEGORY_PLATFORM,
                component="Coordination Engine",
                check_name="KServe Proxy",
                status="WARNING",
                details=f"KServe proxy response invalid: {str(e)}",
                url=url,
                remediation="Check coordination engine logs for KServe integration errors"
            )
    else:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Coordination Engine",
            check_name="KServe Proxy",
            status="WARNING",
            details=details if details else "KServe proxy endpoint not accessible",
            url=url,
            remediation="Verify ENABLE_KSERVE_INTEGRATION=true in coordination engine deployment"
        )


def validate_model_serving() -> List[Dict[str, Any]]:
    """Validate KServe InferenceServices"""
    checks = []

    # Get registered models from coordination engine dynamically
    try:
        import requests
        response = requests.get(f"{COORDINATION_ENGINE_URL}/api/v1/models", timeout=10)
        if response.status_code == 200:
            models = response.json().get('models', [])
            if not models:
                # Fallback to default if no models registered
                models = ["anomaly-detector", "predictive-analytics"]
                logger.warning("No models registered in coordination engine - using defaults")
        else:
            # Fallback to default if endpoint fails
            models = ["anomaly-detector", "predictive-analytics"]
            logger.warning("Could not fetch models from coordination engine - using defaults")
    except Exception as e:
        # Fallback to default on error
        models = ["anomaly-detector", "predictive-analytics"]
        logger.warning(f"Error fetching models: {e} - using defaults")

    for model_name in models:
        success, output = _run_oc_command([
            "oc", "get", "inferenceservice", model_name,
            "-n", "self-healing-platform",
            "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"
        ])

        if success and output == "True":
            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Model Serving",
                check_name=f"InferenceService: {model_name}",
                status="PASSED",
                details="InferenceService ready"
            ))
        elif success and output:
            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Model Serving",
                check_name=f"InferenceService: {model_name}",
                status="WARNING",
                details=f"InferenceService exists but not ready (status: {output})",
                remediation=f"Models will be deployed via notebooks; check: oc get inferenceservice {model_name} -n self-healing-platform"
            ))
        else:
            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Model Serving",
                check_name=f"InferenceService: {model_name}",
                status="WARNING",
                details="InferenceService not yet deployed (will be created by notebooks)",
                remediation=f"This is expected before notebook execution; models deployed in Phase 04"
            ))

    return checks


def validate_object_storage() -> List[Dict[str, Any]]:
    """Validate S3/ODF object storage accessibility"""
    checks = []

    # Check for S3 credentials
    access_key = os.getenv("AWS_ACCESS_KEY_ID")
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")

    if access_key and secret_key:
        checks.append(_create_check_result(
            category=CATEGORY_PLATFORM,
            component="Object Storage",
            check_name="S3 Credentials",
            status="PASSED",
            details="AWS credentials available"
        ))

        # Try to connect to S3
        if not BOTO3_AVAILABLE:
            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Object Storage",
                check_name="S3 Connectivity",
                status="WARNING",
                details="boto3 not available in current environment",
                remediation="boto3 will be available in RHODS workbench"
            ))
            return checks

        try:
            # Support both S3_ENDPOINT_URL and AWS_S3_ENDPOINT for compatibility
            endpoint_url = os.getenv("S3_ENDPOINT_URL") or os.getenv("AWS_S3_ENDPOINT")
            s3_client = boto3.client(
                "s3",
                aws_access_key_id=access_key,
                aws_secret_access_key=secret_key,
                endpoint_url=endpoint_url,
                verify=False
            )

            # Try to list buckets
            response = s3_client.list_buckets()
            bucket_count = len(response.get("Buckets", []))

            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Object Storage",
                check_name="S3 Connectivity",
                status="PASSED",
                details=f"Connected successfully, {bucket_count} bucket(s) found"
            ))

            # Check for model-storage bucket
            bucket_names = [b["Name"] for b in response.get("Buckets", [])]
            if "model-storage" in bucket_names:
                checks.append(_create_check_result(
                    category=CATEGORY_PLATFORM,
                    component="Object Storage",
                    check_name="model-storage Bucket",
                    status="PASSED",
                    details="Bucket exists"
                ))
            else:
                checks.append(_create_check_result(
                    category=CATEGORY_PLATFORM,
                    component="Object Storage",
                    check_name="model-storage Bucket",
                    status="WARNING",
                    details="Bucket not found (will be created by notebooks)",
                    remediation="Bucket will be created during notebook execution"
                ))

        except (ClientError, NoCredentialsError) as e:
            checks.append(_create_check_result(
                category=CATEGORY_PLATFORM,
                component="Object Storage",
                check_name="S3 Connectivity",
                status="FAILED",
                details=f"Connection failed: {str(e)[:100]}",
                remediation="Check AWS_S3_ENDPOINT (or S3_ENDPOINT_URL) and credentials in model-storage-config secret"
            ))
    else:
        checks.append(_create_check_result(
            category=CATEGORY_PLATFORM,
            component="Object Storage",
            check_name="S3 Credentials",
            status="WARNING",
            details="AWS credentials not found in environment",
            remediation="Credentials may be provided via ExternalSecrets; check: oc get externalsecret model-storage-credentials -n self-healing-platform"
        ))

    return checks


def validate_mcp_server() -> Dict[str, Any]:
    """Validate MCP server connectivity"""
    url = f"{MCP_SERVER_URL}/health"
    success, status_code, details, elapsed_ms = _http_get_with_retry(url)

    if success and status_code == 200:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="MCP Server",
            check_name="Health Endpoint",
            status="PASSED",
            details=details,
            url=url,
            response_time_ms=elapsed_ms
        )
    else:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="MCP Server",
            check_name="Health Endpoint",
            status="WARNING",
            details=details,
            url=url,
            remediation="MCP server optional for Phase 01-05 notebooks; required for Phase 06"
        )


def validate_prometheus() -> Dict[str, Any]:
    """Validate Prometheus query API using ServiceAccount token for authentication"""
    url = f"{THANOS_URL}/api/v1/query?query=up"
    # Use ServiceAccount token for authentication - requires cluster-monitoring-view ClusterRole
    success, status_code, details, elapsed_ms = _http_get_with_retry(url, verify=False, use_sa_token=True)

    if success and status_code == 200:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Monitoring",
            check_name="Prometheus Query API",
            status="PASSED",
            details=details,
            url=url,
            response_time_ms=elapsed_ms
        )
    else:
        return _create_check_result(
            category=CATEGORY_PLATFORM,
            component="Monitoring",
            check_name="Prometheus Query API",
            status="WARNING",
            details=details,
            url=url,
            remediation="Check ServiceAccount has cluster-monitoring-view ClusterRole binding"
        )


# =============================================================================
# OPENSHIFT COMPONENTS VALIDATION
# =============================================================================

def validate_argocd_applications() -> Dict[str, Any]:
    """Validate ArgoCD applications"""
    success, output = _run_oc_command([
        "oc", "get", "application", "self-healing-platform",
        "-n", "openshift-gitops",
        "-o", "jsonpath={.status.health.status}"
    ])

    if success:
        if output == "Healthy":
            return _create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="ArgoCD",
                check_name="Application: self-healing-platform",
                status="PASSED",
                details="Application healthy and synced"
            )
        elif output:
            return _create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="ArgoCD",
                check_name="Application: self-healing-platform",
                status="WARNING",
                details=f"Application status: {output}",
                remediation="Check ArgoCD: oc get application self-healing-platform -n openshift-gitops"
            )
        else:
            return _create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="ArgoCD",
                check_name="Application: self-healing-platform",
                status="WARNING",
                details="Application not found (may not be deployed via ArgoCD)",
                remediation="If using Helm directly, this is expected"
            )
    else:
        return _create_check_result(
            category=CATEGORY_OPENSHIFT,
            component="ArgoCD",
            check_name="Application: self-healing-platform",
            status="WARNING",
            details="Could not query ArgoCD applications",
            remediation="Check if ArgoCD is installed: oc get pods -n openshift-gitops"
        )


def validate_tekton_pipelines() -> List[Dict[str, Any]]:
    """Validate Tekton pipelines"""
    checks = []

    pipelines = [
        "deployment-validation-pipeline",
        "model-serving-validation-pipeline"
    ]

    for pipeline_name in pipelines:
        success, output = _run_oc_command([
            "oc", "get", "pipeline", pipeline_name,
            "-n", "openshift-pipelines",
            "-o", "jsonpath={.metadata.name}"
        ])

        if success and output == pipeline_name:
            checks.append(_create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="Tekton",
                check_name=f"Pipeline: {pipeline_name}",
                status="PASSED",
                details="Pipeline exists"
            ))
        else:
            checks.append(_create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="Tekton",
                check_name=f"Pipeline: {pipeline_name}",
                status="WARNING",
                details="Pipeline not found (not critical for notebook execution)",
                remediation="Pipelines used for automated validation; not required for manual notebook execution"
            ))

    return checks


def validate_external_secrets() -> List[Dict[str, Any]]:
    """Validate External Secrets Operator resources"""
    checks = []

    # Check SecretStore
    success, output = _run_oc_command([
        "oc", "get", "secretstore", "kubernetes-secret-store",
        "-n", "self-healing-platform",
        "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"
    ])

    if success and output == "True":
        checks.append(_create_check_result(
            category=CATEGORY_OPENSHIFT,
            component="External Secrets",
            check_name="SecretStore",
            status="PASSED",
            details="SecretStore ready"
        ))
    else:
        checks.append(_create_check_result(
            category=CATEGORY_OPENSHIFT,
            component="External Secrets",
            check_name="SecretStore",
            status="WARNING",
            details="SecretStore not ready or not found",
            remediation="Check: oc get secretstore -n self-healing-platform"
        ))

    # Check ExternalSecrets
    external_secrets = ["gitea-credentials", "registry-credentials", "database-credentials"]

    for es_name in external_secrets:
        success, output = _run_oc_command([
            "oc", "get", "externalsecret", es_name,
            "-n", "self-healing-platform",
            "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"
        ])

        if success and output == "True":
            checks.append(_create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="External Secrets",
                check_name=f"ExternalSecret: {es_name}",
                status="PASSED",
                details="ExternalSecret synced"
            ))
        elif success:
            checks.append(_create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="External Secrets",
                check_name=f"ExternalSecret: {es_name}",
                status="WARNING",
                details="ExternalSecret exists but not synced",
                remediation=f"Check: oc get externalsecret {es_name} -n self-healing-platform -o yaml"
            ))
        else:
            checks.append(_create_check_result(
                category=CATEGORY_OPENSHIFT,
                component="External Secrets",
                check_name=f"ExternalSecret: {es_name}",
                status="WARNING",
                details="ExternalSecret not found",
                remediation="Some secrets may be optional depending on deployment method"
            ))

    return checks


# =============================================================================
# REPORT GENERATION
# =============================================================================

def generate_validation_report(checks: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Generate comprehensive validation report

    Args:
        checks: List of validation check results

    Returns:
        Validation report with summary and detailed checks
    """
    passed = sum(1 for c in checks if c['status'] == 'PASSED')
    failed = sum(1 for c in checks if c['status'] == 'FAILED')
    warnings = sum(1 for c in checks if c['status'] == 'WARNING')

    # Determine overall status
    if failed > 0:
        overall_status = "FAILED"
    elif warnings > 5:  # More than 5 warnings = degraded
        overall_status = "DEGRADED"
    else:
        overall_status = "PASSED"

    report = {
        "validation_date": datetime.utcnow().isoformat() + "Z",
        "validation_status": overall_status,
        "summary": {
            "total_checks": len(checks),
            "passed": passed,
            "failed": failed,
            "warnings": warnings
        },
        "checks": checks
    }

    # Save report to file
    report_path = "/opt/app-root/src/.config/validation-report.json"
    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    return report


def print_validation_report(report: Dict[str, Any]) -> None:
    """
    Print validation report in human-readable format

    Args:
        report: Validation report dictionary
    """
    print("=" * 80)
    print("🚀 PLATFORM READINESS VALIDATION REPORT")
    print("=" * 80)
    print()

    # Overall status
    status = report["validation_status"]
    status_icon = "✅" if status == "PASSED" else ("⚠️" if status == "DEGRADED" else "❌")
    print(f"Status: {status_icon} {status}")
    print(f"Date: {report['validation_date']}")
    print()

    # Summary
    summary = report["summary"]
    print("Summary:")
    print(f"  Total Checks: {summary['total_checks']}")
    print(f"  ✅ Passed: {summary['passed']}")
    print(f"  ❌ Failed: {summary['failed']}")
    print(f"  ⚠️  Warnings: {summary['warnings']}")
    print()

    # Group checks by category
    categories = {}
    for check in report["checks"]:
        cat = check["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(check)

    # Print by category
    for category, checks in categories.items():
        print("-" * 80)
        print(f"📁 {category}")
        print("-" * 80)

        for check in checks:
            status_icon = {
                "PASSED": "✅",
                "FAILED": "❌",
                "WARNING": "⚠️"
            }.get(check["status"], "❓")

            component = check["component"]
            check_name = check["check"]
            details = check["details"]

            print(f"{status_icon} {component} - {check_name}")
            print(f"   {details}")

            if "url" in check:
                print(f"   URL: {check['url']}")
            if "response_time_ms" in check:
                print(f"   Response Time: {check['response_time_ms']}ms")
            if "remediation" in check and check["remediation"]:
                print(f"   💡 Remediation: {check['remediation']}")
            print()

    print("=" * 80)

    if status == "PASSED":
        print("✅ Platform is ready for notebook execution!")
        print()
        print("Next Steps:")
        print("  1. Start with Phase 01: Data Collection")
        print("  2. Follow notebook execution order (01 → 08)")
        print("  3. Refer to notebooks/README.md for complete guide")
    elif status == "DEGRADED":
        print("⚠️  Platform has warnings but may be usable")
        print()
        print("Next Steps:")
        print("  1. Review warnings above")
        print("  2. Determine if warnings are blocking for your use case")
        print("  3. Address critical warnings before proceeding")
    else:
        print("❌ Platform is NOT ready - critical failures detected")
        print()
        print("Next Steps:")
        print("  1. Review failed checks above")
        print("  2. Apply remediations")
        print("  3. Re-run this validation notebook")
        print("  4. Contact administrator if issues persist")

    print("=" * 80)
