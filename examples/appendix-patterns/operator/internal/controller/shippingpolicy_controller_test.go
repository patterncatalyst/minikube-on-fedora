package controller

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	shippingv1alpha1 "github.com/patterncatalyst/shipping-policy-operator/api/v1alpha1"
)

// newTestScheme builds the same scheme main.go registers, so the fake client
// understands ShippingPolicy, Deployment, and ConfigMap.
func newTestScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add client-go scheme: %v", err)
	}
	if err := shippingv1alpha1.AddToScheme(scheme); err != nil {
		t.Fatalf("add shipping scheme: %v", err)
	}
	return scheme
}

func samplePolicy() *shippingv1alpha1.ShippingPolicy {
	return &shippingv1alpha1.ShippingPolicy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ground-standard",
			Namespace: "patterns",
			// A nonzero generation lets the test assert
			// ObservedGeneration propagates onto the Ready condition the
			// way a real apiserver-assigned generation would.
			Generation: 1,
		},
		Spec: shippingv1alpha1.ShippingPolicySpec{
			Carrier:           "ground",
			MaxTransitDays:    5,
			Replicas:          3,
			PriorityClassName: "patterns-high-priority",
		},
	}
}

// reconcile is a small helper that runs one Reconcile call against req built
// from policy's own namespace/name.
func reconcile(t *testing.T, r *ShippingPolicyReconciler, policy *shippingv1alpha1.ShippingPolicy) ctrl.Result {
	t.Helper()
	res, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace},
	})
	if err != nil {
		t.Fatalf("Reconcile returned error: %v", err)
	}
	return res
}

// TestReconcile_CreatesDeploymentAndConfigMap asserts the first reconcile of
// a new ShippingPolicy creates exactly the child Deployment and ConfigMap
// the chapter describes, with replicas, priority class, and policy data
// sourced from the spec.
func TestReconcile_CreatesDeploymentAndConfigMap(t *testing.T) {
	scheme := newTestScheme(t)
	policy := samplePolicy()

	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(policy).
		WithStatusSubresource(&shippingv1alpha1.ShippingPolicy{}).
		Build()

	r := &ShippingPolicyReconciler{Client: fakeClient, Scheme: scheme}
	reconcile(t, r, policy)

	var deploy appsv1.Deployment
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: "ground-standard", Namespace: "patterns"}, &deploy); err != nil {
		t.Fatalf("expected Deployment to exist: %v", err)
	}
	if got, want := *deploy.Spec.Replicas, int32(3); got != want {
		t.Errorf("Deployment replicas = %d, want %d", got, want)
	}
	if got, want := deploy.Spec.Template.Spec.PriorityClassName, "patterns-high-priority"; got != want {
		t.Errorf("Deployment priorityClassName = %q, want %q", got, want)
	}
	if got, want := deploy.Spec.Template.Spec.Containers[0].Image, shippingServiceImage; got != want {
		t.Errorf("container image = %q, want %q", got, want)
	}
	if got, want := deploy.Spec.Template.Spec.Containers[0].ImagePullPolicy, corev1.PullNever; got != want {
		t.Errorf("imagePullPolicy = %q, want %q", got, want)
	}

	// Owner reference: deleting the ShippingPolicy must garbage-collect this
	// Deployment without a finalizer.
	if len(deploy.OwnerReferences) != 1 || deploy.OwnerReferences[0].Name != policy.Name {
		t.Errorf("Deployment owner references = %+v, want one ref to %q", deploy.OwnerReferences, policy.Name)
	}
	if deploy.OwnerReferences[0].Controller == nil || !*deploy.OwnerReferences[0].Controller {
		t.Errorf("Deployment owner reference is not a controller reference: %+v", deploy.OwnerReferences[0])
	}

	var cm corev1.ConfigMap
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: "ground-standard", Namespace: "patterns"}, &cm); err != nil {
		t.Fatalf("expected ConfigMap to exist: %v", err)
	}
	if got, want := cm.Data["carrier"], "ground"; got != want {
		t.Errorf("ConfigMap carrier = %q, want %q", got, want)
	}
	if got, want := cm.Data["maxTransitDays"], "5"; got != want {
		t.Errorf("ConfigMap maxTransitDays = %q, want %q", got, want)
	}
	if len(cm.OwnerReferences) != 1 || cm.OwnerReferences[0].Name != policy.Name {
		t.Errorf("ConfigMap owner references = %+v, want one ref to %q", cm.OwnerReferences, policy.Name)
	}
}

// TestReconcile_StatusReadyOnceReplicasMatch asserts the Ready condition
// tracks the gap between desired (spec.replicas) and observed
// (status.replicas on the child Deployment): False while a Deployment
// controller hasn't caught up, True once it has, with ObservedGeneration set
// from the ShippingPolicy's own generation either way.
func TestReconcile_StatusReadyOnceReplicasMatch(t *testing.T) {
	scheme := newTestScheme(t)
	policy := samplePolicy()

	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(policy).
		WithStatusSubresource(&shippingv1alpha1.ShippingPolicy{}).
		Build()

	r := &ShippingPolicyReconciler{Client: fakeClient, Scheme: scheme}
	reconcile(t, r, policy)

	var afterFirst shippingv1alpha1.ShippingPolicy
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &afterFirst); err != nil {
		t.Fatalf("get ShippingPolicy: %v", err)
	}
	readyCond := findCondition(afterFirst.Status.Conditions, shippingv1alpha1.ShippingPolicyConditionReady)
	if readyCond == nil {
		t.Fatalf("expected a Ready condition, got none in %+v", afterFirst.Status.Conditions)
	}
	// The fake client, like a real cluster immediately after a Deployment is
	// created, has not yet populated status.replicas (no Deployment
	// controller is running against the fake client), so Ready must read
	// False here.
	if readyCond.Status != metav1.ConditionFalse {
		t.Errorf("Ready condition = %v before status.replicas catches up, want False", readyCond.Status)
	}
	if readyCond.ObservedGeneration != policy.Generation {
		t.Errorf("Ready ObservedGeneration = %d, want %d", readyCond.ObservedGeneration, policy.Generation)
	}
	if afterFirst.Status.ObservedReplicas != 0 {
		t.Errorf("ObservedReplicas = %d, want 0 before the Deployment reports status", afterFirst.Status.ObservedReplicas)
	}

	// Simulate a Deployment controller catching up: patch the child
	// Deployment's status.replicas to match the desired count, then
	// reconcile again.
	var deploy appsv1.Deployment
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &deploy); err != nil {
		t.Fatalf("get Deployment: %v", err)
	}
	deploy.Status.Replicas = 3
	if err := fakeClient.Status().Update(context.Background(), &deploy); err != nil {
		t.Fatalf("update Deployment status: %v", err)
	}

	reconcile(t, r, policy)

	var afterSecond shippingv1alpha1.ShippingPolicy
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &afterSecond); err != nil {
		t.Fatalf("get ShippingPolicy: %v", err)
	}
	readyCond = findCondition(afterSecond.Status.Conditions, shippingv1alpha1.ShippingPolicyConditionReady)
	if readyCond == nil || readyCond.Status != metav1.ConditionTrue {
		t.Fatalf("Ready condition after replicas catch up = %+v, want True", readyCond)
	}
	if afterSecond.Status.ObservedReplicas != 3 {
		t.Errorf("ObservedReplicas = %d, want 3", afterSecond.Status.ObservedReplicas)
	}
}

// TestReconcile_IsIdempotent asserts running Reconcile twice in a row with no
// spec change produces no further writes worth noting: the second call
// leaves the Deployment's spec identical, which is the level-triggered
// contract the Controller chapter (22) describes.
func TestReconcile_IsIdempotent(t *testing.T) {
	scheme := newTestScheme(t)
	policy := samplePolicy()

	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(policy).
		WithStatusSubresource(&shippingv1alpha1.ShippingPolicy{}).
		Build()

	r := &ShippingPolicyReconciler{Client: fakeClient, Scheme: scheme}
	reconcile(t, r, policy)

	var first appsv1.Deployment
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &first); err != nil {
		t.Fatalf("get Deployment: %v", err)
	}
	firstGeneration := first.Generation

	reconcile(t, r, policy)

	var second appsv1.Deployment
	if err := fakeClient.Get(context.Background(), types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &second); err != nil {
		t.Fatalf("get Deployment: %v", err)
	}
	if *second.Spec.Replicas != *first.Spec.Replicas {
		t.Errorf("replicas changed across idempotent reconciles: %d -> %d", *first.Spec.Replicas, *second.Spec.Replicas)
	}
	if second.Generation != firstGeneration {
		t.Errorf("Deployment generation changed on a no-op reconcile: %d -> %d (spec was rewritten identically instead of left alone)", firstGeneration, second.Generation)
	}
}

func findCondition(conditions []metav1.Condition, condType string) *metav1.Condition {
	for i := range conditions {
		if conditions[i].Type == condType {
			return &conditions[i]
		}
	}
	return nil
}
