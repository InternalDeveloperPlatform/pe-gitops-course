{{- define "templateLibrary.cilium.CiliumNetworkPolicy.tpl" -}}
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: {{ .Release.Name | printf "%s-%s" .Chart.Name }}
  namespace: {{ .Release.Namespace }}
spec: {}
{{- end -}}
{{- define "templateLibrary.cilium.CiliumNetworkPolicy" -}}
{{- include "templateLibrary.util.merge" (append . "templateLibrary.cilium.CiliumNetworkPolicy.tpl") -}}
{{- end -}}
