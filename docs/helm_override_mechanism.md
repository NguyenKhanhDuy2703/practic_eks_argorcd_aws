# Giải thích cơ chế Override của Helm trong ArgoCD

Tài liệu này giải thích cách chúng ta đã tổ chức cấu trúc thư mục CD sử dụng **Helm**, và cơ chế giúp chúng ta cấu hình riêng biệt cho từng môi trường (sandbox, staging, prod) mà không cần phải copy lại toàn bộ manifest (DRY - Don't Repeat Yourself).

---

## 1. Cấu trúc thư mục Helm Chart hiện tại

Chúng ta đã thiết kế chuẩn Helm Chart tại đường dẫn `cd/components/app/`.

```text
cd/components/app/
├── Chart.yaml              # File khai báo metadata (siêu dữ liệu) của Helm Chart
├── templates/              # Thư mục chứa các "khuôn" YAML
│   ├── deployment.yaml     # Khuôn tạo ra Deployment
│   └── service.yaml        # Khuôn tạo ra Service
├── values.yaml             # File chứa các GIÁ TRỊ GỐC (Base values)
├── values-sandbox.yaml     # File GHI ĐÈ cho môi trường Sandbox
└── values-prod.yaml        # File GHI ĐÈ cho môi trường Production
```

Dưới đây là giải thích chi tiết cấu trúc, nội dung và tác dụng của từng file.

---

## 2. Phân tích chi tiết từng file và tác dụng

### 2.1. File `Chart.yaml`
**Tác dụng:** Đây là "chứng minh nhân dân" của thư mục ứng dụng. Khi có file này, thư mục `app` sẽ chính thức được ArgoCD và Helm nhận diện là một ứng dụng có thể triển khai (một Helm Chart).

**Cấu trúc bên trong:**
```yaml
apiVersion: v2             # Phiên bản chuẩn API của Helm 3
name: ai-engine            # Tên của Chart (ứng dụng)
description: A Helm chart for AI Engine Microservice # Mô tả
type: application          # Loại Chart là ứng dụng (chứ không phải thư viện library)
version: 1.0.0             # Phiên bản của cái Chart này
appVersion: "1.0.0"        # Phiên bản phần mềm chạy bên trong Chart
```

### 2.2. Thư mục `templates/`
Thư mục này chứa các file `.yaml` nhưng được viết bằng ngôn ngữ template của Go. Thay vì viết cứng thông số (hardcode), ta dùng ký hiệu `{{ ... }}` để chừa chỗ trống. Chỗ trống này sẽ được lấp đầy bằng các biến đọc từ file `values.yaml`.

#### A. File `templates/deployment.yaml`
**Tác dụng:** Đây là khuôn mẫu sinh ra Kubernetes Deployment. Deployment chịu trách nhiệm quản lý số lượng Pods, image chạy bên trong Pods, tài nguyên (CPU/RAM) cấp cho Pods và các biến môi trường của App.

**Cấu trúc quan trọng:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}       # Tự động lấy "ai-engine" từ Chart.yaml
spec:
  replicas: {{ .Values.replicaCount }} # Lấy số lượng pod từ values.yaml
  template:
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}" # Ghép link Image và Tag
          resources:
            {{- toYaml .Values.resources | nindent 12 }} # Copy nguyên xi khối resources ở values.yaml vào đây
          env:
            # Đây là đoạn lặp cực kỳ mạnh mẽ của Helm.
            # Nó duyệt qua danh sách biến môi trường trong values.yaml và đẻ ra từng dòng - name / value
            {{- range $key, $val := .Values.env }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
```

#### B. File `templates/service.yaml`
**Tác dụng:** Sinh ra Kubernetes Service, dùng để mở port kết nối nội bộ hoặc ra bên ngoài cho các Pods thuộc Deployment phía trên.

**Cấu trúc quan trọng:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Chart.Name }}
spec:
  type: {{ .Values.service.type }}   # Lấy kiểu mạng (ClusterIP, NodePort...)
  ports:
    - port: {{ .Values.service.port }} # Lấy port cần mở (Ví dụ: 8080)
```

---

### 2.3. Các file Values (Biến số)

Nhiệm vụ của Helm là bơm (inject) các giá trị vào trong các "chỗ trống" ở thư mục `templates`. Vậy giá trị đó lấy từ đâu? Chính là từ các file Values.

#### A. File Giá trị gốc: `values.yaml`
**Tác dụng:** Chứa **toàn bộ các cấu hình mặc định**. Đây là cấu hình chuẩn nhất của ứng dụng, thường dùng chung cho mọi môi trường.

**Cấu trúc bên trong:**
```yaml
replicaCount: 1                  # Mặc định chạy 1 pod

image:
  repository: tf1/ai-engine
  tag: "latest"                  # Mặc định dùng image mới nhất

service:
  type: ClusterIP                # Mặc định mạng nội bộ
  port: 8080

resources:                       # Tài nguyên mặc định (Nhẹ)
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

env:                             # Biến môi trường mặc định
  ENVIRONMENT: "default"
  LOG_LEVEL: "info"
```

#### B. File Ghi đè: `values-sandbox.yaml`
**Tác dụng:** Chứa các cấu hình **đặc thù chỉ dành cho Sandbox**. Bất cứ dòng nào xuất hiện ở file này sẽ đè nát dòng tương ứng ở file `values.yaml` gốc. Dòng nào KHÔNG CÓ thì sẽ dùng lại giá trị gốc.

**Cấu trúc bên trong:**
```yaml
# KHÔNG CẦN khai báo lại "image.repository" hay "service.type", Helm tự lấy từ values.yaml gốc.
# Chỉ ghi đè những gì khác biệt.

image:
  tag: "sandbox-a1b2c3d"         # Ghi đè tag riêng của code nhánh sandbox

resources:
  requests:
    cpu: 50m                     # Ép tài nguyên thấp xuống cho môi trường test
    memory: 64Mi

env:
  ENVIRONMENT: "sandbox"         # Ghi đè biến này
  DEBUG_MODE: "true"             # Thêm một biến HOÀN TOÀN MỚI chỉ Sandbox mới có
```

#### C. File Ghi đè: `values-prod.yaml`
**Tác dụng:** Tương tự Sandbox, nhưng dành cho Production (Thực tế).

**Cấu trúc bên trong:**
```yaml
replicaCount: 3                  # Bắt buộc tăng số Pod lên 3 để chịu lỗi

image:
  tag: "prod-x9y8z7w"            # Tag xịn đã qua kiểm duyệt

resources:
  requests:
    cpu: 500m                    # Cấp RAM/CPU siêu lớn
    memory: 512Mi

env:
  ENVIRONMENT: "prod"
  LOG_LEVEL: "error"             # Đổi log level để đỡ tốn dung lượng
```

---

## 3. Cách khai báo với ArgoCD

Sau khi đã hiểu bản chất từng file, để ArgoCD triển khai ứng dụng cho môi trường **Sandbox**, ta sẽ khai báo ở nơi khác (thường là trong App of Apps) cấu hình Application tương tự như sau:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-engine-sandbox
spec:
  source:
    repoURL: https://github.com/NguyenKhanhDuy2703/pra_eks.git
    path: cd/components/app
    targetRevision: main
    helm:
      # BƯỚC QUAN TRỌNG: ArgoCD mặc định đọc `values.yaml`. 
      # Thuộc tính valueFiles dưới đây ép ArgoCD đọc thêm `values-sandbox.yaml` và merge chúng lại!
      valueFiles:
        - values-sandbox.yaml 
  destination:
    server: https://kubernetes.default.svc
    namespace: sandbox
```

Bằng cách đổi giá trị `valueFiles` thành `- values-prod.yaml` và namespace thành `prod`, bạn dễ dàng nhân bản ứng dụng ra vô số môi trường khác nhau mà vẫn đảm bảo mã nguồn CD tinh gọn tuyệt đối!
