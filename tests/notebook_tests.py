#!/usr/bin/env python3
"""
Comprehensive notebook testing suite using Papermill
Tests all notebooks for execution, data validation, and integration
"""

import os
import sys
import json
import tempfile
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional
import pandas as pd
import papermill as pm
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class NotebookTester:
    """
    Comprehensive notebook testing using Papermill
    """

    def __init__(self, notebooks_dir: str = "notebooks"):
        self.notebooks_dir = Path(notebooks_dir)
        self.test_results = {}
        self.temp_dir = tempfile.mkdtemp(prefix="notebook_tests_")

        # Define test configurations for each notebook
        self.notebook_configs = {
            "01-data-collection/prometheus-metrics-collection.ipynb": {
                "timeout": 300,  # 5 minutes
                "parameters": {
                    "TEST_MODE": True,
                    "SYNTHETIC_DATA_ONLY": True,
                    "MAX_METRICS": 100
                },
                "expected_outputs": ["metrics_df", "processed_metrics"],
                "data_validations": [
                    {"variable": "metrics_df", "type": "DataFrame", "min_rows": 1},
                    {"variable": "processed_metrics", "type": "dict", "required_keys": ["cpu", "memory"]}
                ]
            },
            "02-anomaly-detection/01-isolation-forest-implementation.ipynb": {
                "timeout": 600,  # 10 minutes
                "parameters": {
                    "TEST_MODE": True,
                    "SYNTHETIC_DATA_ONLY": True,
                    "N_SAMPLES": 100
                },
                "expected_outputs": ["anomaly_scores", "model"],
                "data_validations": [
                    {"variable": "anomaly_scores", "type": "ndarray", "min_length": 50},
                    {"variable": "model", "type": "object", "has_method": "predict"}
                ]
            },
            "01-data-collection/openshift-events-analysis.ipynb": {
                "timeout": 300,
                "parameters": {
                    "TEST_MODE": True,
                    "SYNTHETIC_DATA_ONLY": True,
                    "EVENT_COUNT": 50
                },
                "expected_outputs": ["events_df", "event_patterns"],
                "data_validations": [
                    {"variable": "events_df", "type": "DataFrame", "min_rows": 10},
                    {"variable": "event_patterns", "type": "dict", "required_keys": ["event_types", "reasons"]}
                ]
            },
            "01-data-collection/log-parsing-analysis.ipynb": {
                "timeout": 300,
                "parameters": {
                    "TEST_MODE": True,
                    "SYNTHETIC_DATA_ONLY": True,
                    "LOG_COUNT": 100
                },
                "expected_outputs": ["parsed_logs_df", "error_matches_df"],
                "data_validations": [
                    {"variable": "parsed_logs_df", "type": "DataFrame", "min_rows": 50},
                    {"variable": "error_matches_df", "type": "DataFrame", "min_rows": 0}
                ]
            },
            "01-data-collection/feature-store-demo.ipynb": {
                "timeout": 400,
                "parameters": {
                    "TEST_MODE": True,
                    "SYNTHETIC_DATA_ONLY": True,
                    "FEATURE_COUNT": 50
                },
                "expected_outputs": ["feature_store", "infra_df", "app_df"],
                "data_validations": [
                    {"variable": "infra_df", "type": "DataFrame", "min_rows": 20},
                    {"variable": "app_df", "type": "DataFrame", "min_rows": 10},
                    {"variable": "feature_store", "type": "object", "has_method": "write_features"}
                ]
            }
        }

    def run_notebook_test(self, notebook_path: str, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Run a single notebook test with Papermill
        """
        logger.info(f"Testing notebook: {notebook_path}")

        full_path = self.notebooks_dir / notebook_path
        if not full_path.exists():
            return {
                "status": "SKIPPED",
                "error": f"Notebook not found: {full_path}",
                "execution_time": 0
            }

        output_path = Path(self.temp_dir) / f"test_{notebook_path.replace('/', '_')}"
        output_path.parent.mkdir(parents=True, exist_ok=True)

        start_time = datetime.now()

        try:
            # Execute notebook with Papermill
            pm.execute_notebook(
                str(full_path),
                str(output_path),
                parameters=config.get("parameters", {}),
                execution_timeout=config.get("timeout", 300),
                kernel_name="python3"
            )

            execution_time = (datetime.now() - start_time).total_seconds()

            # Validate outputs
            validation_results = self._validate_notebook_outputs(output_path, config)

            return {
                "status": "PASSED" if validation_results["all_passed"] else "FAILED",
                "execution_time": execution_time,
                "output_path": str(output_path),
                "validations": validation_results,
                "error": None
            }

        except Exception as e:
            execution_time = (datetime.now() - start_time).total_seconds()
            logger.error(f"Notebook execution failed: {e}")

            return {
                "status": "FAILED",
                "execution_time": execution_time,
                "output_path": str(output_path) if output_path.exists() else None,
                "validations": {"all_passed": False, "errors": [str(e)]},
                "error": str(e)
            }

    def _validate_notebook_outputs(self, output_path: Path, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate notebook outputs and data quality
        """
        validation_results = {
            "all_passed": True,
            "validations": [],
            "errors": []
        }

        try:
            # Load executed notebook
            with open(output_path, 'r') as f:
                notebook = json.load(f)

            # Extract variables from notebook cells
            notebook_vars = self._extract_notebook_variables(notebook)

            # Run data validations
            for validation in config.get("data_validations", []):
                result = self._run_validation(notebook_vars, validation)
                validation_results["validations"].append(result)

                if not result["passed"]:
                    validation_results["all_passed"] = False
                    validation_results["errors"].append(result["error"])

            # Check expected outputs exist
            for expected_output in config.get("expected_outputs", []):
                if expected_output not in notebook_vars:
                    validation_results["all_passed"] = False
                    validation_results["errors"].append(f"Expected output '{expected_output}' not found")
                else:
                    validation_results["validations"].append({
                        "type": "output_exists",
                        "variable": expected_output,
                        "passed": True,
                        "error": None
                    })

        except Exception as e:
            validation_results["all_passed"] = False
            validation_results["errors"].append(f"Validation error: {str(e)}")

        return validation_results

    def _extract_notebook_variables(self, notebook: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extract variables from executed notebook cells
        """
        variables = {}

        for cell in notebook.get("cells", []):
            if cell.get("cell_type") == "code":
                # Look for variable assignments in outputs
                for output in cell.get("outputs", []):
                    if output.get("output_type") == "execute_result":
                        # This is a simplified extraction - in practice, you might need
                        # more sophisticated parsing or use nbformat/papermill features
                        pass

        # For now, return empty dict - in practice, you'd extract actual variables
        # This would require more sophisticated notebook introspection
        return variables

    def _run_validation(self, variables: Dict[str, Any], validation: Dict[str, Any]) -> Dict[str, Any]:
        """
        Run a single data validation
        """
        var_name = validation["variable"]

        if var_name not in variables:
            return {
                "type": "data_validation",
                "variable": var_name,
                "passed": False,
                "error": f"Variable '{var_name}' not found in notebook outputs"
            }

        # For now, return passed - in practice, you'd implement actual validation logic
        return {
            "type": "data_validation",
            "variable": var_name,
            "passed": True,
            "error": None
        }

    def run_all_tests(self) -> Dict[str, Any]:
        """
        Run all notebook tests
        """
        logger.info("Starting comprehensive notebook testing...")

        results = {
            "timestamp": datetime.now().isoformat(),
            "total_notebooks": len(self.notebook_configs),
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "notebooks": {}
        }

        for notebook_path, config in self.notebook_configs.items():
            test_result = self.run_notebook_test(notebook_path, config)
            results["notebooks"][notebook_path] = test_result

            if test_result["status"] == "PASSED":
                results["passed"] += 1
            elif test_result["status"] == "FAILED":
                results["failed"] += 1
            else:
                results["skipped"] += 1

        results["success_rate"] = results["passed"] / results["total_notebooks"] * 100

        logger.info(f"Testing completed: {results['passed']}/{results['total_notebooks']} passed")
        return results

    def generate_report(self, results: Dict[str, Any], output_file: str = "notebook_test_report.json"):
        """
        Generate comprehensive test report
        """
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)

        logger.info(f"Test report saved to: {output_file}")

        # Print summary
        print("\n" + "="*60)
        print("NOTEBOOK TESTING SUMMARY")
        print("="*60)
        print(f"Total Notebooks: {results['total_notebooks']}")
        print(f"Passed: {results['passed']}")
        print(f"Failed: {results['failed']}")
        print(f"Skipped: {results['skipped']}")
        print(f"Success Rate: {results['success_rate']:.1f}%")
        print("="*60)

        # Print individual results
        for notebook, result in results["notebooks"].items():
            status_icon = "✅" if result["status"] == "PASSED" else "❌" if result["status"] == "FAILED" else "⏭️"
            print(f"{status_icon} {notebook}: {result['status']} ({result['execution_time']:.1f}s)")
            if result["error"]:
                print(f"   Error: {result['error']}")

def main():
    """
    Main entry point for notebook testing
    """
    tester = NotebookTester()
    results = tester.run_all_tests()
    tester.generate_report(results)

    # Exit with error code if any tests failed
    if results["failed"] > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
