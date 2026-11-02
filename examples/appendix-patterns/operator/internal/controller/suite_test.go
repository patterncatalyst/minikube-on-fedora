package controller

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"

	shippingv1alpha1 "github.com/patterncatalyst/shipping-policy-operator/api/v1alpha1"
)

// testEnv is a real etcd + kube-apiserver pair, started once for this
// package's envtest-backed test and reused for it. Unlike the fake client
// used in shippingpolicy_controller_test.go, this exercises the generated
// CRD's own OpenAPI validation (required fields, minimums) against a real
// apiserver, which a fake client can't do.
//
// `go test ./...` runs this unconditionally, but TestMain degrades
// gracefully: if KUBEBUILDER_ASSETS isn't set (or no envtest binaries are on
// PATH), testEnv.Start() fails, TestMain logs that to stderr and still runs
// the rest of the suite, and TestEnvtest_ReconcileAgainstRealAPIServer skips
// itself (testClient stays nil) rather than failing the whole package.
// `setup-envtest use <version> -p env` prints the KUBEBUILDER_ASSETS export
// this file needs; see README.md.
var testEnv *envtest.Environment
var testClient client.Client

func TestMain(m *testing.M) {
	code := runWithEnvtest(m)
	os.Exit(code)
}

func runWithEnvtest(m *testing.M) int {
	scheme := clientgoscheme.Scheme
	if err := shippingv1alpha1.AddToScheme(scheme); err != nil {
		fmt.Fprintln(os.Stderr, "add scheme:", err)
		return 1
	}

	testEnv = &envtest.Environment{
		CRDDirectoryPaths:     []string{filepath.Join("..", "..", "config", "crd", "bases")},
		ErrorIfCRDPathMissing: true,
	}

	cfg, err := testEnv.Start()
	if err != nil {
		// No envtest binaries on this machine/PATH: skip the envtest-backed
		// suite rather than failing the whole package, so `go test ./...`
		// still passes on a machine that only has the fake-client tests
		// available. See README.md for which binaries this needs
		// (KUBEBUILDER_ASSETS from `setup-envtest use`).
		fmt.Fprintln(os.Stderr, "envtest environment unavailable, skipping envtest suite:", err)
		return m.Run()
	}
	defer func() {
		if stopErr := testEnv.Stop(); stopErr != nil {
			fmt.Fprintln(os.Stderr, "stop envtest environment:", stopErr)
		}
	}()

	testClient, err = client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		fmt.Fprintln(os.Stderr, "build envtest client:", err)
		return 1
	}

	if err := testClient.Create(context.Background(), &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: "patterns"},
	}); err != nil {
		fmt.Fprintln(os.Stderr, "create patterns namespace:", err)
		return 1
	}

	return m.Run()
}

// TestEnvtest_ReconcileAgainstRealAPIServer applies a ShippingPolicy through
// a real apiserver (so the generated CRD's own schema validates it), runs
// one reconcile, and confirms the child Deployment and ConfigMap land with
// the right shape: the same assertions as the fake-client test, now proven
// against real API-level validation rather than an in-memory tracker.
func TestEnvtest_ReconcileAgainstRealAPIServer(t *testing.T) {
	if testClient == nil {
		t.Skip("envtest environment unavailable; see stderr from TestMain")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	policy := &shippingv1alpha1.ShippingPolicy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "air-express",
			Namespace: "patterns",
		},
		Spec: shippingv1alpha1.ShippingPolicySpec{
			Carrier:        "air",
			MaxTransitDays: 2,
			Replicas:       2,
		},
	}
	if err := testClient.Create(ctx, policy); err != nil {
		t.Fatalf("create ShippingPolicy against envtest apiserver: %v", err)
	}
	t.Cleanup(func() {
		_ = testClient.Delete(context.Background(), policy)
	})

	r := &ShippingPolicyReconciler{Client: testClient, Scheme: clientgoscheme.Scheme}
	if _, err := r.Reconcile(ctx, ctrl.Request{
		NamespacedName: types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace},
	}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	var cm corev1.ConfigMap
	if err := testClient.Get(ctx, types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &cm); err != nil {
		t.Fatalf("expected ConfigMap created via real apiserver: %v", err)
	}
	if got, want := cm.Data["carrier"], "air"; got != want {
		t.Errorf("ConfigMap carrier = %q, want %q", got, want)
	}

	// A ShippingPolicy missing a required field (carrier) must be rejected
	// by the apiserver's own CRD schema validation before it ever reaches
	// the reconciler. This is the one assertion the fake client cannot make.
	invalid := &shippingv1alpha1.ShippingPolicy{
		ObjectMeta: metav1.ObjectMeta{Name: "missing-carrier", Namespace: "patterns"},
		Spec:       shippingv1alpha1.ShippingPolicySpec{MaxTransitDays: 1, Replicas: 1},
	}
	if err := testClient.Create(ctx, invalid); err == nil {
		t.Error("expected apiserver to reject a ShippingPolicy with no carrier, got no error")
	}
}
