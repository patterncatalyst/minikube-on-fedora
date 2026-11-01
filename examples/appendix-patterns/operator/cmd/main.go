// Command shipping-policy-operator runs the ShippingPolicy controller as a
// standalone manager process. It is the binary the Containerfile builds and
// the Deployment in config/manager runs: it watches ShippingPolicy objects
// across the cluster (scoped to the patterns namespace by the RBAC in
// config/rbac, not by the manager's own cache) and reconciles each one's
// child Deployment and ConfigMap.
package main

import (
	"flag"
	"os"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	shippingv1alpha1 "github.com/patterncatalyst/shipping-policy-operator/api/v1alpha1"
	"github.com/patterncatalyst/shipping-policy-operator/internal/controller"
)

var scheme = clientgoscheme.Scheme

func init() {
	utilruntime.Must(appsv1.AddToScheme(scheme))
	utilruntime.Must(corev1.AddToScheme(scheme))
	utilruntime.Must(shippingv1alpha1.AddToScheme(scheme))
}

func main() {
	var metricsAddr string
	var probeAddr string
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8443", "The address the metrics endpoint binds to.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")
	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		HealthProbeBindAddress: probeAddr,
		// Metrics are exposed over plain HTTP on a localhost-only address by
		// default upstream; this appendix doesn't wire Prometheus scraping
		// for the operator, so the bind address only matters for the
		// liveness of the metrics server itself.
	})
	if err != nil {
		setupLogAndExit("unable to start manager", err)
	}

	if err = (&controller.ShippingPolicyReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLogAndExit("unable to create controller", err)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLogAndExit("unable to set up health check", err)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLogAndExit("unable to set up ready check", err)
	}

	ctrl.Log.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLogAndExit("problem running manager", err)
	}
}

func setupLogAndExit(msg string, err error) {
	ctrl.Log.Error(err, msg)
	os.Exit(1)
}
