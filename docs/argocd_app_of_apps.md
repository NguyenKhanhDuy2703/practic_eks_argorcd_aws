# Hướng dẫn chi tiết: Kiến trúc ArgoCD "App of Apps"

Tài liệu này giải thích chi tiết các đoạn code YAML cho kiến trúc ArgoCD App of Apps, giúp bạn kiểm soát và hiểu rõ cấu trúc triển khai CI/CD.

Dự kiến sử dụng **Helm** làm công cụ sinh template chính cùng với **Kyverno** cho phần Admission. Git URL repository được sử dụng là: `https://github.com/NguyenKhanhDuy2703/pra_eks.git`.

---

## 1. Cấu trúc Helm của "App of Apps" (Thư mục `argocd-apps/`)

### File `argocd-apps/Chart.yaml`

Đây là file định nghĩa cho Helm Chart gốc.

```yaml
apiVersion: v2
name: argocd-apps
description: A Helm chart for ArgoCD App of Apps (Root Application)
type: application
version: 1.0.0
appVersion: "1.0.0"
```
**Giải thích chi tiết:**
- `apiVersion: v2`: Sử dụng chuẩn Helm 3.
- `name: argocd-apps`: Tên của Helm chart.
- Các dòng còn lại: Cung cấp thông tin phiên bản và mô tả. Đây là chuẩn cơ bản của mọi Helm chart.

---

### File `argocd-apps/values.yaml`

Đây là file quan trọng nhất của App of Apps. Nó chứa mọi biến (variables) cho các ứng dụng con. Chỉ cần đổi ở đây, cấu hình sẽ được áp dụng cho toàn bộ.

```yaml
spec:
  # URL của Git repo chứa source code này
  source:
    repoURL: https://github.com/NguyenKhanhDuy2703/pra_eks.git
    targetRevision: main # Nhánh được theo dõi
  
  # Cấu hình đích đến của ArgoCD
  destination:
    server: https://kubernetes.default.svc # Deploy thẳng vào cluster hiện tại đang chạy ArgoCD
    namespace: argocd

# Bật / Tắt các component
components:
  argocdConfig: true
  monitoring: true
  rbac: true
  admission: true
```
**Giải thích chi tiết:**
- Khối `spec.source`: Cung cấp thông tin repo để các App con biết chúng cần clone mã nguồn từ đâu (`repoURL`) và từ nhánh nào (`targetRevision`).
- Khối `spec.destination`: Chỉ định nơi các ứng dụng sẽ được cài đặt. `https://kubernetes.default.svc` có nghĩa là cài vào chính cụm Kubernetes đang chạy ArgoCD.
- Khối `components`: Cho phép bạn linh hoạt bật/tắt cài đặt từng module. Ví dụ: Nếu không muốn cài `monitoring` lúc này, chỉ cần đổi `true` thành `false`.

---

## 2. Các ứng dụng con (Templates của App of Apps)

### File `argocd-apps/templates/monitoring.yaml`

Đây là file tạo ra một Application ArgoCD để cài đặt Prometheus và Grafana.

```yaml
{{- if .Values.components.monitoring }}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    # Lấy Helm chart trực tiếp từ repo chính thức của Prometheus cộng đồng
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 58.2.1 # Phiên bản helm chart
    helm:
      valueFiles:
        # Đường dẫn trỏ tới file values tuỳ chỉnh được lưu trong Git repo của BẠN
        - {{ .Values.spec.source.repoURL }}/infrastructure/monitoring/values-override.yaml
  destination:
    server: {{ .Values.spec.destination.server }}
    namespace: monitoring # Tạo mọi thứ ở namespace monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
{{- end }}
```

**Giải thích chi tiết:**
- `{{- if .Values.components.monitoring }}`: Điều kiện của Helm, chỉ tạo file này nếu trong `values.yaml` phần monitoring được set là `true`.
- `apiVersion` và `kind: Application`: Đây là Resource tùy chỉnh (CRD) của ArgoCD. Nó báo cho ArgoCD biết đây là một "ứng dụng" cần quản lý.
- `finalizers: resources-finalizer...`: Đảm bảo rằng khi bạn xoá Application này trong ArgoCD, nó sẽ xoá sạch các tài nguyên (pods, services...) trong cụm.
- Khối `source`: 
  - `repoURL` và `chart`: Khai báo lấy chart trực tiếp từ kho cộng đồng. Việc này là best-practice, thay vì copy toàn bộ mã nguồn của họ về repo của mình.
  - `helm.valueFiles`: Đây là điểm mấu chốt. Dù lấy chart từ ngoài, nhưng các tham số (values) lại được lấy từ một file lưu trên Git Repo của *chính bạn*.
- `destination.namespace: monitoring`: Cho biết Prometheus/Grafana sẽ chạy ở namespace `monitoring`.
- `syncPolicy.automated`: Bật chế độ tự động đồng bộ. Nếu có thay đổi trên Git, tự động apply vào cluster (`selfHeal`). Đồng thời tự động xoá tài nguyên cũ (`prune`) và tự động tạo namespace nếu chưa có (`CreateNamespace=true`).

---

### File `argocd-apps/templates/admission.yaml`

Cài đặt Kyverno - Công cụ Admission Controller để đảm bảo an ninh/chính sách.

```yaml
{{- if .Values.components.admission }}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://kyverno.github.io/kyverno/
    chart: kyverno
    targetRevision: 3.1.4
  destination:
    server: {{ .Values.spec.destination.server }}
    namespace: kyverno
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
{{- end }}
```
**Giải thích chi tiết:**
Tương tự monitoring, đoạn mã này gọi trực tiếp Helm chart của Kyverno.

Và thêm một Application nữa để đồng bộ các **Policies** do chính bạn tự viết (nằm trong thư mục `infrastructure/admission`).

```yaml
---
{{- if .Values.components.admission }}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno-policies
  namespace: argocd
spec:
  project: default
  source:
    repoURL: {{ .Values.spec.source.repoURL }}
    path: infrastructure/admission # Nơi chứa YAML policies của bạn
    targetRevision: {{ .Values.spec.source.targetRevision }}
  destination:
    server: {{ .Values.spec.destination.server }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
{{- end }}
```
**Giải thích chi tiết:**
- `source.path: infrastructure/admission`: Khác với việc tải Helm, phần này tải các manifest YAML tĩnh do bạn tự viết ở thư mục `infrastructure/admission/` từ Git Repo của bạn.
- Cả hai kết hợp lại: ArgoCD sẽ lo cài phần lõi Kyverno, sau đó đồng bộ các chính sách (policies) bảo mật do bạn định nghĩa vào cluster.

---

### File `argocd-apps/templates/rbac.yaml`

Cài đặt RBAC tĩnh cho cluster.

```yaml
{{- if .Values.components.rbac }}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-rbac
  namespace: argocd
spec:
  project: default
  source:
    repoURL: {{ .Values.spec.source.repoURL }}
    path: infrastructure/rbac
    targetRevision: {{ .Values.spec.source.targetRevision }}
  destination:
    server: {{ .Values.spec.destination.server }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
{{- end }}
```
**Giải thích chi tiết:**
Chỉ đơn giản là bảo ArgoCD quét thư mục `infrastructure/rbac` trong repo của bạn và apply toàn bộ file YAML (Role, ClusterRole...) trong đó vào hệ thống.
