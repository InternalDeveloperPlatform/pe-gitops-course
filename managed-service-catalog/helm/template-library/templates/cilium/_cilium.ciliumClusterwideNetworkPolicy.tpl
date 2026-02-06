{{- define "templateLibrary.cilium.CiliumClusterwideNetworkPolicy.tpl" -}}
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: {{ .Release.Name | printf "%s-%s" .Chart.Name }}
spec: {}
{{- end -}}
{{- define "templateLibrary.cilium.CiliumClusterwideNetworkPolicy" -}}
{{- include "templateLibrary.util.merge" (append . "templateLibrary.cilium.CiliumClusterwideNetworkPolicy.tpl") -}}
{{- end -}}
