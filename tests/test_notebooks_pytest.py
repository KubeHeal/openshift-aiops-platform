#!/usr/bin/env python3
"""
Pytest-based notebook testing for integration with standard testing frameworks
"""

import os
import pytest
import tempfile
import papermill as pm
from pathlib import Path
import json
import pandas as pd
from datetime import datetime

# Test configuration
NOTEBOOKS_DIR = Path(__file__).parent.parent / "notebooks"
TEST_TIMEOUT = 300  # 5 minutes default

class TestNotebooks:
    """
    Pytest class for notebook testing
    """

    @pytest.fixture(scope="class")
    def temp_output_dir(self):
        """Create temporary directory for test outputs"""
        with tempfile.TemporaryDirectory(prefix="pytest_notebooks_") as temp_dir:
            yield temp_dir

    @pytest.fixture(autouse=True)
    def setup_test_environment(self):
        """Setup test environment variables"""
        os.environ["TEST_MODE"] = "true"
        os.environ["SYNTHETIC_DATA_ONLY"] = "true"
        os.environ["NOTEBOOK_TEST_MODE"] = "true"
        yield
        # Cleanup if needed

    def execute_notebook(self, notebook_path: Path, output_path: Path, parameters: dict = None):
        """
        Execute a notebook with papermill and return execution info
        """
        if parameters is None:
            parameters = {
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True
            }

        start_time = datetime.now()

        try:
            pm.execute_notebook(
                str(notebook_path),
                str(output_path),
                parameters=parameters,
                execution_timeout=TEST_TIMEOUT,
                kernel_name="python3"
            )

            execution_time = (datetime.now() - start_time).total_seconds()
            return {
                "success": True,
                "execution_time": execution_time,
                "error": None
            }

        except Exception as e:
            execution_time = (datetime.now() - start_time).total_seconds()
            return {
                "success": False,
                "execution_time": execution_time,
                "error": str(e)
            }

    @pytest.mark.data_collection
    def test_prometheus_metrics_collection(self, temp_output_dir):
        """Test Prometheus metrics collection notebook"""
        notebook_path = NOTEBOOKS_DIR / "01-data-collection" / "prometheus-metrics-collection.ipynb"
        output_path = Path(temp_output_dir) / "test_prometheus_metrics.ipynb"

        if not notebook_path.exists():
            pytest.skip(f"Notebook not found: {notebook_path}")

        result = self.execute_notebook(
            notebook_path,
            output_path,
            parameters={
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True,
                "MAX_METRICS": 50
            }
        )

        assert result["success"], f"Notebook execution failed: {result['error']}"
        assert result["execution_time"] < TEST_TIMEOUT, f"Execution took too long: {result['execution_time']}s"
        assert output_path.exists(), "Output notebook was not created"

    @pytest.mark.data_collection
    def test_openshift_events_analysis(self, temp_output_dir):
        """Test OpenShift events analysis notebook"""
        notebook_path = NOTEBOOKS_DIR / "01-data-collection" / "openshift-events-analysis.ipynb"
        output_path = Path(temp_output_dir) / "test_events_analysis.ipynb"

        if not notebook_path.exists():
            pytest.skip(f"Notebook not found: {notebook_path}")

        result = self.execute_notebook(
            notebook_path,
            output_path,
            parameters={
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True,
                "EVENT_COUNT": 30
            }
        )

        assert result["success"], f"Notebook execution failed: {result['error']}"
        assert result["execution_time"] < TEST_TIMEOUT, f"Execution took too long: {result['execution_time']}s"

    @pytest.mark.data_collection
    def test_log_parsing_analysis(self, temp_output_dir):
        """Test log parsing analysis notebook"""
        notebook_path = NOTEBOOKS_DIR / "01-data-collection" / "log-parsing-analysis.ipynb"
        output_path = Path(temp_output_dir) / "test_log_parsing.ipynb"

        if not notebook_path.exists():
            pytest.skip(f"Notebook not found: {notebook_path}")

        result = self.execute_notebook(
            notebook_path,
            output_path,
            parameters={
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True,
                "LOG_COUNT": 50
            }
        )

        assert result["success"], f"Notebook execution failed: {result['error']}"
        assert result["execution_time"] < TEST_TIMEOUT, f"Execution took too long: {result['execution_time']}s"

    @pytest.mark.data_collection
    def test_feature_store_demo(self, temp_output_dir):
        """Test feature store demo notebook"""
        notebook_path = NOTEBOOKS_DIR / "01-data-collection" / "feature-store-demo.ipynb"
        output_path = Path(temp_output_dir) / "test_feature_store.ipynb"

        if not notebook_path.exists():
            pytest.skip(f"Notebook not found: {notebook_path}")

        result = self.execute_notebook(
            notebook_path,
            output_path,
            parameters={
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True,
                "FEATURE_COUNT": 25
            }
        )

        assert result["success"], f"Notebook execution failed: {result['error']}"
        assert result["execution_time"] < 400, f"Execution took too long: {result['execution_time']}s"  # Longer timeout for feature store

    @pytest.mark.anomaly_detection
    def test_isolation_forest_implementation(self, temp_output_dir):
        """Test Isolation Forest anomaly detection notebook"""
        notebook_path = NOTEBOOKS_DIR / "02-anomaly-detection" / "isolation-forest-implementation.ipynb"
        output_path = Path(temp_output_dir) / "test_isolation_forest.ipynb"

        if not notebook_path.exists():
            pytest.skip(f"Notebook not found: {notebook_path}")

        result = self.execute_notebook(
            notebook_path,
            output_path,
            parameters={
                "TEST_MODE": True,
                "SYNTHETIC_DATA_ONLY": True,
                "N_SAMPLES": 100
            }
        )

        assert result["success"], f"Notebook execution failed: {result['error']}"
        assert result["execution_time"] < 600, f"Execution took too long: {result['execution_time']}s"  # Longer timeout for ML

class TestNotebookDataValidation:
    """
    Additional tests for data validation and quality checks
    """

    @pytest.mark.data_validation
    def test_common_functions_import(self):
        """Test that common functions can be imported"""
        import sys
        sys.path.append(str(NOTEBOOKS_DIR / "utils"))

        try:
            from common_functions import setup_environment, validate_data_quality
            assert callable(setup_environment)
            assert callable(validate_data_quality)
        except ImportError as e:
            pytest.fail(f"Failed to import common functions: {e}")

    @pytest.mark.data_validation
    def test_mcp_client_import(self):
        """Test that MCP client can be imported"""
        import sys
        sys.path.append(str(NOTEBOOKS_DIR / "utils"))

        try:
            from mcp_client import MCPClient
            assert MCPClient is not None
        except ImportError as e:
            pytest.fail(f"Failed to import MCP client: {e}")

# Pytest configuration for different test runs
def pytest_configure(config):
    """Configure pytest markers"""
    config.addinivalue_line(
        "markers", "data_collection: mark test as data collection notebook test"
    )
    config.addinivalue_line(
        "markers", "anomaly_detection: mark test as anomaly detection notebook test"
    )
    config.addinivalue_line(
        "markers", "self_healing: mark test as self-healing logic notebook test"
    )
    config.addinivalue_line(
        "markers", "data_validation: mark test as data validation test"
    )

# Custom pytest collection for notebook discovery
def pytest_collect_file(parent, path):
    """Custom collection to handle notebook files if needed"""
    # This could be extended to automatically discover and test notebooks
    return None
