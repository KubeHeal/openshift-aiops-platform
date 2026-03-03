#!/usr/bin/env python3
"""
ADR Validation Report Generator

Generates comprehensive markdown and JSON reports from validation results.
Compares SNO vs HA topologies and analyzes failures.
"""

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any
from collections import defaultdict

# Project root
PROJECT_ROOT = Path(__file__).parent.parent
RESULTS_DIR = PROJECT_ROOT / "results"
DOCS_DIR = PROJECT_ROOT / "docs" / "adrs"
AUDIT_DIR = DOCS_DIR / "audit-reports"


class ValidationReportGenerator:
    def __init__(self, sno_file: Path, ha_file: Path = None):
        self.sno_file = sno_file
        self.ha_file = ha_file
        self.sno_results = self._load_json(sno_file) if sno_file.exists() else []
        self.ha_results = self._load_json(ha_file) if ha_file and ha_file.exists() else []
        self.timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        self.date_str = datetime.utcnow().strftime("%Y-%m-%d")

    @staticmethod
    def _load_json(file_path: Path) -> List[Dict]:
        """Load JSON file"""
        try:
            with open(file_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Failed to load {file_path}: {e}", file=sys.stderr)
            return []

    def _categorize_adr(self, adr: str) -> str:
        """Categorize ADR by number"""
        adr_num = int(adr)
        if adr_num in [1, 3, 4, 6, 7, 10]:
            return "Core Platform"
        elif adr_num in [11, 12, 13, 29, 31, 32]:
            return "Notebooks & Development"
        elif adr_num in [21, 23, 24, 25, 26, 42, 43]:
            return "MLOps & CI/CD"
        elif adr_num in [19, 30]:
            return "Deployment & GitOps"
        elif adr_num in [36, 38]:
            return "Coordination & LLM"
        elif adr_num in [34, 35, 54, 55, 56, 57, 58]:
            return "Storage & Topology"
        else:
            return "Other"

    def generate_summary_stats(self) -> Dict:
        """Generate summary statistics"""
        def count_status(results):
            counts = defaultdict(int)
            for result in results:
                counts[result.get('status', 'UNKNOWN')] += 1
            return dict(counts)

        sno_counts = count_status(self.sno_results)
        ha_counts = count_status(self.ha_results)

        total_sno = sum(v for k, v in sno_counts.items() if k not in ['N/A'])
        total_ha = sum(v for k, v in ha_counts.items() if k not in ['N/A'])

        return {
            "validation_date": self.timestamp,
            "total_adrs_validated": 31,
            "sno": {
                "total": total_sno,
                "pass": sno_counts.get('PASS', 0),
                "fail": sno_counts.get('FAIL', 0),
                "partial": sno_counts.get('PARTIAL', 0),
                "error": sno_counts.get('ERROR', 0),
                "na": sno_counts.get('N/A', 0),
                "success_rate": round(sno_counts.get('PASS', 0) * 100 / total_sno, 1) if total_sno > 0 else 0
            },
            "ha": {
                "total": total_ha,
                "pass": ha_counts.get('PASS', 0),
                "fail": ha_counts.get('FAIL', 0),
                "partial": ha_counts.get('PARTIAL', 0),
                "error": ha_counts.get('ERROR', 0),
                "na": ha_counts.get('N/A', 0),
                "success_rate": round(ha_counts.get('PASS', 0) * 100 / total_ha, 1) if total_ha > 0 else 0
            } if self.ha_results else None
        }

    def generate_category_breakdown(self) -> Dict:
        """Generate breakdown by category"""
        categories = defaultdict(lambda: {"pass": 0, "fail": 0, "partial": 0, "adrs": []})

        for result in self.sno_results:
            adr = result.get('adr', 'unknown')
            category = self._categorize_adr(adr)
            status = result.get('status', 'UNKNOWN')

            if status == 'PASS':
                categories[category]["pass"] += 1
            elif status == 'FAIL':
                categories[category]["fail"] += 1
            elif status == 'PARTIAL':
                categories[category]["partial"] += 1

            categories[category]["adrs"].append(adr)

        return dict(categories)

    def identify_failures(self) -> List[Dict]:
        """Identify and categorize failures"""
        failures = []

        for result in self.sno_results:
            if result.get('status') in ['FAIL', 'ERROR']:
                failures.append({
                    "adr": result.get('adr'),
                    "cluster": "SNO",
                    "status": result.get('status'),
                    "expected": result.get('expected'),
                    "actual": result.get('actual'),
                    "details": result.get('details')
                })

        for result in self.ha_results:
            if result.get('status') in ['FAIL', 'ERROR']:
                failures.append({
                    "adr": result.get('adr'),
                    "cluster": "HA",
                    "status": result.get('status'),
                    "expected": result.get('expected'),
                    "actual": result.get('actual'),
                    "details": result.get('details')
                })

        return failures

    def identify_topology_differences(self) -> List[Dict]:
        """Identify differences between SNO and HA"""
        if not self.ha_results:
            return []

        differences = []
        sno_by_adr = {r['adr']: r for r in self.sno_results}
        ha_by_adr = {r['adr']: r for r in self.ha_results}

        for adr in sno_by_adr:
            if adr not in ha_by_adr:
                continue

            sno_status = sno_by_adr[adr].get('status')
            ha_status = ha_by_adr[adr].get('status')

            if sno_status != ha_status or adr == '056':  # ADR-056 is SNO-specific
                differences.append({
                    "adr": adr,
                    "sno_status": sno_status,
                    "ha_status": ha_status,
                    "sno_details": sno_by_adr[adr].get('details'),
                    "ha_details": ha_by_adr[adr].get('details')
                })

        return differences

    def generate_json_report(self) -> Dict:
        """Generate comprehensive JSON report"""
        return {
            "report_metadata": {
                "generated_at": self.timestamp,
                "validation_date": self.date_str,
                "report_version": "1.0"
            },
            "summary": self.generate_summary_stats(),
            "by_category": self.generate_category_breakdown(),
            "failures": self.identify_failures(),
            "topology_differences": self.identify_topology_differences()
        }

    def generate_markdown_report(self, json_report: Dict) -> str:
        """Generate markdown report"""
        md = []

        # Header
        md.append(f"# ADR Implementation Validation Report")
        md.append(f"")
        md.append(f"**Validation Date:** {self.date_str}")
        md.append(f"**Report Generated:** {self.timestamp}")
        md.append(f"")

        # Executive Summary
        summary = json_report['summary']
        md.append(f"## Executive Summary")
        md.append(f"")
        md.append(f"This report validates the implementation of **31 ADRs** across both SNO (Single Node OpenShift) and HA (Highly Available) cluster topologies.")
        md.append(f"")

        # SNO Summary
        sno = summary['sno']
        md.append(f"### SNO Cluster Results")
        md.append(f"")
        md.append(f"| Metric | Count | Percentage |")
        md.append(f"|--------|-------|------------|")
        md.append(f"| ✅ PASS | {sno['pass']} | {sno['success_rate']}% |")
        md.append(f"| ❌ FAIL | {sno['fail']} | {round(sno['fail'] * 100 / sno['total'], 1) if sno['total'] > 0 else 0}% |")
        md.append(f"| ⚠️ PARTIAL | {sno['partial']} | {round(sno['partial'] * 100 / sno['total'], 1) if sno['total'] > 0 else 0}% |")
        md.append(f"| **Total Validated** | **{sno['total']}** | **100%** |")
        md.append(f"")

        # HA Summary (if available)
        if summary['ha']:
            ha = summary['ha']
            md.append(f"### HA Cluster Results")
            md.append(f"")
            md.append(f"| Metric | Count | Percentage |")
            md.append(f"|--------|-------|------------|")
            md.append(f"| ✅ PASS | {ha['pass']} | {ha['success_rate']}% |")
            md.append(f"| ❌ FAIL | {ha['fail']} | {round(ha['fail'] * 100 / ha['total'], 1) if ha['total'] > 0 else 0}% |")
            md.append(f"| ⚠️ PARTIAL | {ha['partial']} | {round(ha['partial'] * 100 / ha['total'], 1) if ha['total'] > 0 else 0}% |")
            md.append(f"| **Total Validated** | **{ha['total']}** | **100%** |")
            md.append(f"")

        # Category Breakdown
        md.append(f"## Validation by Category")
        md.append(f"")
        md.append(f"| Category | PASS | FAIL | PARTIAL | ADRs |")
        md.append(f"|----------|------|------|---------|------|")

        for category, stats in sorted(json_report['by_category'].items()):
            adrs = ', '.join(sorted(stats['adrs']))
            md.append(f"| {category} | {stats['pass']} | {stats['fail']} | {stats['partial']} | {adrs} |")

        md.append(f"")

        # Failures
        if json_report['failures']:
            md.append(f"## Failures and Issues")
            md.append(f"")
            md.append(f"The following ADRs failed validation or encountered errors:")
            md.append(f"")

            for failure in json_report['failures']:
                md.append(f"### ADR-{failure['adr']} ({failure['cluster']})")
                md.append(f"")
                md.append(f"- **Status:** {failure['status']}")
                md.append(f"- **Expected:** {failure['expected']}")
                md.append(f"- **Actual:** {failure['actual']}")
                md.append(f"- **Details:** {failure['details']}")
                md.append(f"")

        # Topology Differences
        if json_report['topology_differences']:
            md.append(f"## Topology-Specific Variations")
            md.append(f"")
            md.append(f"The following ADRs show different results between SNO and HA topologies:")
            md.append(f"")

            for diff in json_report['topology_differences']:
                md.append(f"### ADR-{diff['adr']}")
                md.append(f"")
                md.append(f"- **SNO Status:** {diff['sno_status']} - {diff['sno_details']}")
                md.append(f"- **HA Status:** {diff['ha_status']} - {diff['ha_details']}")
                md.append(f"")

        # Recommendations
        md.append(f"## Recommendations")
        md.append(f"")

        if sno['success_rate'] >= 90:
            md.append(f"✅ **SNO cluster validation passed** with {sno['success_rate']}% success rate.")
        else:
            md.append(f"⚠️ **SNO cluster requires attention** - {sno['fail'] + sno['partial']} ADRs need remediation.")

        if summary['ha'] and ha['success_rate'] >= 90:
            md.append(f"✅ **HA cluster validation passed** with {ha['success_rate']}% success rate.")
        elif summary['ha']:
            md.append(f"⚠️ **HA cluster requires attention** - {ha['fail'] + ha['partial']} ADRs need remediation.")

        md.append(f"")
        md.append(f"### Next Steps")
        md.append(f"")
        md.append(f"1. **Address Failures:** Review and remediate failed ADRs")
        md.append(f"2. **Update Documentation:** Update IMPLEMENTATION-TRACKER.md with validation evidence")
        md.append(f"3. **Sync to Aggregator:** Re-sync corrected status to ADR Aggregator dashboard")
        md.append(f"4. **Partial Implementations:** Complete partially implemented ADRs (027, 038)")
        md.append(f"")

        # Footer
        md.append(f"---")
        md.append(f"")
        md.append(f"*Report generated by: `scripts/generate-validation-report.py`*")
        md.append(f"")

        return '\n'.join(md)

    def save_reports(self):
        """Save both JSON and Markdown reports"""
        # Ensure audit directory exists
        AUDIT_DIR.mkdir(parents=True, exist_ok=True)

        # Generate reports
        json_report = self.generate_json_report()
        md_report = self.generate_markdown_report(json_report)

        # Save JSON report
        json_file = RESULTS_DIR / "validation-report.json"
        with open(json_file, 'w') as f:
            json.dump(json_report, f, indent=2)
        print(f"✓ JSON report saved: {json_file}")

        # Save Markdown report
        md_file = AUDIT_DIR / f"adr-validation-{self.date_str}.md"
        with open(md_file, 'w') as f:
            f.write(md_report)
        print(f"✓ Markdown report saved: {md_file}")

        # Print summary to console
        print("\n" + "="*60)
        print("Validation Summary")
        print("="*60)
        summary = json_report['summary']
        print(f"SNO: {summary['sno']['pass']} PASS, {summary['sno']['fail']} FAIL, {summary['sno']['partial']} PARTIAL ({summary['sno']['success_rate']}%)")
        if summary['ha']:
            print(f"HA:  {summary['ha']['pass']} PASS, {summary['ha']['fail']} FAIL, {summary['ha']['partial']} PARTIAL ({summary['ha']['success_rate']}%)")
        print("="*60)


def main():
    """Main entry point"""
    # Check for results files
    sno_file = RESULTS_DIR / "sno-complete.json"
    ha_file = RESULTS_DIR / "ha-complete.json"

    if not sno_file.exists():
        print(f"Error: SNO results not found at {sno_file}", file=sys.stderr)
        print("Run: scripts/validate-31-adrs.sh --sno-only", file=sys.stderr)
        sys.exit(1)

    # Generate report
    generator = ValidationReportGenerator(sno_file, ha_file)
    generator.save_reports()


if __name__ == "__main__":
    main()
