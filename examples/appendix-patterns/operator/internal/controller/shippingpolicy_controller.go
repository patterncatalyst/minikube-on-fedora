// Package controller holds the ShippingPolicy reconciler: the operator's
// reconcile loop, worked in the Operator chapter (25) and introduced
// conceptually, alongside a bare watch-and-act controller, in the Controller
// chapter (22).
package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	shippingv1alpha1 "github.com/patterncatalyst/shipping-policy-operator/api/v1alpha1"
)

// shippingServiceImage is the image every child Deployment runs. It is the
// same shipping-service image the appendix's other chapters build with
// scripts/build-service.sh and load into the mof-patterns profile; the
// operator never builds or pulls it, only references it with
// imagePullPolicy: Never, exactly like every other Deployment in this
// appendix.
const shippingServiceImage = "shipping-service:v1"

// The shared, disposable Postgres every appendix example points
// shipping-service at (see examples/appendix-patterns/*/00-postgres.yaml).
// The operator's own child Deployment needs the same connection details so
// its Pods actually reach Ready, not just exist.
const (
	postgresHost       = "patterns-postgres.patterns.svc.cluster.local"
	postgresSecretName = "patterns-postgres-app"
	serviceSchema      = "shipping"
)

// ShippingPolicyReconciler reconciles a ShippingPolicy object. Given a
// ShippingPolicy, it owns exactly two child objects in the same namespace: a
// Deployment running shipping-service sized and prioritized from the spec,
// and a ConfigMap carrying the policy's carrier and SLA so the running
// containers can read their own governing policy back out. Both children
// carry a controller owner reference back to the ShippingPolicy, so deleting
// the ShippingPolicy garbage-collects both without a finalizer.
type ShippingPolicyReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=shipping.patterncatalyst.io,resources=shippingpolicies,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=shipping.patterncatalyst.io,resources=shippingpolicies/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch

// Reconcile implements the observe-diff-act loop (chapter 22, Controller):
// read the ShippingPolicy and its children's current state, compute what the
// children should look like, and apply only what's different. It is
// idempotent and level-triggered: running it twice in a row with no spec
// change is a no-op on the cluster, and it never depends on which earlier
// event triggered this particular call.
func (r *ShippingPolicyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var policy shippingv1alpha1.ShippingPolicy
	if err := r.Get(ctx, req.NamespacedName, &policy); err != nil {
		if apierrors.IsNotFound(err) {
			// The ShippingPolicy is gone. Its children carry owner
			// references, so the garbage collector already removed (or is
			// removing) them; there is nothing left for this reconciler to
			// do.
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, fmt.Errorf("get ShippingPolicy: %w", err)
	}

	if err := r.reconcileConfigMap(ctx, &policy); err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile ConfigMap: %w", err)
	}

	observedReplicas, err := r.reconcileDeployment(ctx, &policy)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile Deployment: %w", err)
	}

	if err := r.updateStatus(ctx, &policy, observedReplicas); err != nil {
		return ctrl.Result{}, fmt.Errorf("update status: %w", err)
	}

	logger.Info("reconciled ShippingPolicy",
		"carrier", policy.Spec.Carrier,
		"desiredReplicas", policy.Spec.Replicas,
		"observedReplicas", observedReplicas)

	return ctrl.Result{}, nil
}

// secretKeyRef builds an EnvVarSource reading one key out of a Secret, the
// same secretKeyRef shape every other appendix chapter's shipping-service
// Deployment uses for its Postgres credentials.
func secretKeyRef(name, key string) *corev1.EnvVarSource {
	return &corev1.EnvVarSource{
		SecretKeyRef: &corev1.SecretKeySelector{
			LocalObjectReference: corev1.LocalObjectReference{Name: name},
			Key:                  key,
		},
	}
}

// childName is the name shared by every child object this ShippingPolicy
// owns: the Deployment and the ConfigMap both take the ShippingPolicy's own
// name, since each ShippingPolicy owns exactly one of each.
func childName(policy *shippingv1alpha1.ShippingPolicy) string {
	return policy.Name
}

// reconcileConfigMap creates or updates the ConfigMap carrying this policy's
// carrier and SLA, the shape shipping-service's SERVICE_SCHEMA-style
// configuration reads (chapter 18, Env Var Configuration) applied to a
// policy an operator generates rather than a human-authored manifest.
func (r *ShippingPolicyReconciler) reconcileConfigMap(ctx context.Context, policy *shippingv1alpha1.ShippingPolicy) error {
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      childName(policy),
			Namespace: policy.Namespace,
		},
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, cm, func() error {
		if cm.Data == nil {
			cm.Data = map[string]string{}
		}
		cm.Data["carrier"] = policy.Spec.Carrier
		cm.Data["maxTransitDays"] = fmt.Sprintf("%d", policy.Spec.MaxTransitDays)
		return controllerutil.SetControllerReference(policy, cm, r.Scheme)
	})
	return err
}

// reconcileDeployment creates or updates the Deployment running
// shipping-service under this policy, and returns the Deployment's last
// observed status.replicas for the caller to write into
// ShippingPolicyStatus.
func (r *ShippingPolicyReconciler) reconcileDeployment(ctx context.Context, policy *shippingv1alpha1.ShippingPolicy) (int32, error) {
	deploy := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      childName(policy),
			Namespace: policy.Namespace,
		},
	}

	labels := map[string]string{
		"app.kubernetes.io/name":             "shipping-service",
		"app.kubernetes.io/part-of":          "shipping-policy",
		"app.kubernetes.io/managed-by":       "shipping-policy-operator",
		"shipping.patterncatalyst.io/policy": policy.Name,
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deploy, func() error {
		deploy.Labels = labels
		deploy.Spec.Replicas = &policy.Spec.Replicas
		deploy.Spec.Selector = &metav1.LabelSelector{MatchLabels: labels}
		deploy.Spec.Template.ObjectMeta.Labels = labels
		deploy.Spec.Template.Spec.PriorityClassName = policy.Spec.PriorityClassName
		deploy.Spec.Template.Spec.Containers = []corev1.Container{
			{
				Name:            "shipping-service",
				Image:           shippingServiceImage,
				ImagePullPolicy: corev1.PullNever,
				Ports: []corev1.ContainerPort{
					{ContainerPort: 8080, Name: "http"},
				},
				// SERVICE_SCHEMA/PG_* match every other appendix example's
				// shipping-service Deployment, so a ShippingPolicy's child
				// reaches the same shared patterns-postgres and actually
				// goes Ready. CARRIER/MAXTRANSITDAYS (this policy's own
				// data) come from the ConfigMap below instead, via envFrom.
				Env: []corev1.EnvVar{
					{Name: "SERVICE_SCHEMA", Value: serviceSchema},
					{Name: "PG_HOST", Value: postgresHost},
					{Name: "PG_USER", ValueFrom: secretKeyRef(postgresSecretName, "username")},
					{Name: "PG_PASSWORD", ValueFrom: secretKeyRef(postgresSecretName, "password")},
					{Name: "PG_DATABASE", ValueFrom: secretKeyRef(postgresSecretName, "dbname")},
				},
				EnvFrom: []corev1.EnvFromSource{
					{
						ConfigMapRef: &corev1.ConfigMapEnvSource{
							LocalObjectReference: corev1.LocalObjectReference{Name: childName(policy)},
						},
					},
				},
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceCPU:    resource.MustParse("100m"),
						corev1.ResourceMemory: resource.MustParse("192Mi"),
					},
					Limits: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse("512Mi"),
					},
				},
				StartupProbe: &corev1.Probe{
					ProbeHandler:     corev1.ProbeHandler{HTTPGet: &corev1.HTTPGetAction{Path: "/health", Port: intstr.FromString("http")}},
					FailureThreshold: 30,
					PeriodSeconds:    2,
				},
				ReadinessProbe: &corev1.Probe{
					ProbeHandler:        corev1.ProbeHandler{HTTPGet: &corev1.HTTPGetAction{Path: "/healthz", Port: intstr.FromString("http")}},
					InitialDelaySeconds: 5,
					PeriodSeconds:       5,
				},
			},
		}
		return controllerutil.SetControllerReference(policy, deploy, r.Scheme)
	})
	if err != nil {
		return 0, err
	}

	// Re-read the Deployment so the returned replica count reflects the
	// apiserver's own observed status, not just the spec this reconciler
	// just wrote. On a fake client in a unit test, or immediately after
	// create against a real cluster, status may still read zero until a
	// Deployment controller (or the test) populates it; that is expected
	// and is exactly what ObservedReplicas is for.
	var current appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Name: childName(policy), Namespace: policy.Namespace}, &current); err != nil {
		return 0, err
	}
	return current.Status.Replicas, nil
}

// updateStatus sets ShippingPolicyStatus.ObservedReplicas and maintains a
// single "Ready" condition: Ready is True once the Deployment's observed
// replicas match the spec's desired replica count, and False otherwise.
func (r *ShippingPolicyReconciler) updateStatus(ctx context.Context, policy *shippingv1alpha1.ShippingPolicy, observedReplicas int32) error {
	policy.Status.ObservedReplicas = observedReplicas

	condition := metav1.Condition{
		Type:               shippingv1alpha1.ShippingPolicyConditionReady,
		ObservedGeneration: policy.Generation,
	}
	if observedReplicas == policy.Spec.Replicas {
		condition.Status = metav1.ConditionTrue
		condition.Reason = "ReplicasMatch"
		condition.Message = fmt.Sprintf("observed %d replicas, matching spec", observedReplicas)
	} else {
		condition.Status = metav1.ConditionFalse
		condition.Reason = "ReplicasReconciling"
		condition.Message = fmt.Sprintf("observed %d replicas, want %d", observedReplicas, policy.Spec.Replicas)
	}
	apimeta.SetStatusCondition(&policy.Status.Conditions, condition)

	return r.Status().Update(ctx, policy)
}

// SetupWithManager wires the reconciler into the manager, watching
// ShippingPolicy directly and its two owned child kinds so an out-of-band
// edit to a child (someone hand-editing the Deployment, say) also triggers a
// reconcile, not just a change to the ShippingPolicy itself.
func (r *ShippingPolicyReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&shippingv1alpha1.ShippingPolicy{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.ConfigMap{}).
		Named("shippingpolicy").
		Complete(r)
}
