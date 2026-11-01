package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ShippingPolicySpec declares the fulfillment behavior an operator team wants
// for one carrier lane: which carrier handles it, the transit-time SLA it
// promises, and how many replicas of shipping-service should run to meet
// that SLA.
type ShippingPolicySpec struct {
	// Carrier is the shipping carrier this policy governs, e.g. "ground",
	// "air", or "freight". It is rendered into the child ConfigMap that
	// shipping-service reads at startup.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Carrier string `json:"carrier"`

	// MaxTransitDays is the SLA this policy promises: the maximum number of
	// days a shipment under this carrier may take in transit.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	MaxTransitDays int `json:"maxTransitDays"`

	// Replicas is the number of shipping-service Pods this policy's
	// Deployment should run. The reconciler drives the child Deployment's
	// replica count directly from this field.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	Replicas int32 `json:"replicas"`

	// PriorityClassName, if set, is applied to the child Deployment's Pod
	// template, the same PriorityClass mechanism the Predictable Demands
	// pattern (chapter 01) covers for a plain Deployment.
	// +optional
	PriorityClassName string `json:"priorityClassName,omitempty"`
}

// ShippingPolicyConditionReady is the condition type the reconciler sets once
// the child Deployment's observed replicas match the desired replica count.
const ShippingPolicyConditionReady = "Ready"

// ShippingPolicyStatus reports what the reconciler actually observed on the
// cluster the last time it ran, as distinct from ShippingPolicySpec, which is
// what the operator team asked for.
type ShippingPolicyStatus struct {
	// ObservedReplicas is the child Deployment's status.replicas as last
	// observed by the reconciler.
	// +optional
	ObservedReplicas int32 `json:"observedReplicas,omitempty"`

	// Conditions follow the standard Kubernetes condition convention; the
	// reconciler maintains a single "Ready" condition here.
	// +optional
	// +patchMergeKey=type
	// +patchStrategy=merge
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=shippol
// +kubebuilder:printcolumn:name="Carrier",type=string,JSONPath=`.spec.carrier`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.spec.replicas`
// +kubebuilder:printcolumn:name="Observed",type=integer,JSONPath=`.status.observedReplicas`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// ShippingPolicy is the Schema for the shippingpolicies API. One
// ShippingPolicy describes a single carrier lane's fulfillment policy: the
// Operator chapter's reconciler turns it into a Deployment and a ConfigMap
// carrying that policy's shape, and keeps both in sync with the spec for as
// long as the ShippingPolicy exists.
type ShippingPolicy struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ShippingPolicySpec   `json:"spec,omitempty"`
	Status ShippingPolicyStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ShippingPolicyList contains a list of ShippingPolicy.
type ShippingPolicyList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ShippingPolicy `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ShippingPolicy{}, &ShippingPolicyList{})
}
