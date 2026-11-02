"""shipping-report: a net-new BatchJob/PeriodicJob runner for the
Kubernetes patterns appendix.

Not a capstone data product: a small, disposable CLI that reads rows from
its own `shipping.shipment_events` table (seeded by itself) and writes a
CSV report to a PersistentVolumeClaim, run as a Kubernetes Job (BatchJob
pattern) or a CronJob (PeriodicJob pattern).
"""
