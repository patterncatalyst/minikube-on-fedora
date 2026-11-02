// Command shipping-policy-operator runs the ShippingPolicy controller as a
// standalone manager process. It is the binary the Containerfile builds and
// the Deployment in config/manager runs: it watches ShippingPolicy objects
// in the patterns namespace and reconciles each one's child Deployment and
// ConfigMap.
//
// The manager's cache is restricted to the patterns namespace
// (cache.Options.DefaultNamespaces below) to match the namespaced Role in
// config/rbac. controller-runtime's informer cache does cluster-scoped
// list/watch by default; with only a namespaced Role that default would be
// forbidden ("cannot list ... at the cluster scope") and no reconcile would
// ever fire. Scoping the cache to the one namespace the operator reconciles
// keeps the watches within what the Role grants.
package main

import (
	"flag"
	"os"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	shippingv1alpha1 "github.com/patterncatalyst/shipping-policy-operator/api/v1alpha1"
	"github.com/patterncatalyst/shipping-policy-operator/internal/controller"
)

// operatorNamespace is the single namespace this operator watches and
// reconciles in. It matches the namespaced Role/RoleBinding in config/rbac and
// the Deployment in config/manager, all of which target patterns.
const operatorNamespace = "patterns"

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
		Cache: cache.Options{
			DefaultNamespaces: map[string]cache.Config{operatorNamespace: {}},
		},
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
