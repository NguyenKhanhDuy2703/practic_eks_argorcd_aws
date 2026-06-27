# Sổ tay Kiến thức Kỹ thuật (DevOps / GitOps)

Tài liệu này tổng hợp lại các câu hỏi và khái niệm quan trọng đã được làm rõ trong quá trình xây dựng kiến trúc CI/CD bằng ArgoCD và Helm. Đây là cẩm nang giúp team hiểu rõ "Tại sao chúng ta lại làm như vậy".

---

## 1. Cơ chế của Helm và Kubernetes

### 1.1. Tại sao phải ghi đè biến môi trường (Environment Variables) cho từng nơi?
Thay vì viết một ứng dụng duy nhất chạy ở mọi nơi, ta cần biến môi trường để:
- **Phân tách dữ liệu:** Trỏ đúng về Database test (Sandbox) hoặc Database thật (Prod).
- **Bảo mật:** Sử dụng API Keys test và thật khác nhau để tránh mất tiền oan.
- **Tối ưu giám sát:** Bật `DEBUG_MODE` ở Sandbox để dễ tìm lỗi, nhưng hạ `LOG_LEVEL` xuống mức `error` ở Prod để tiết kiệm dung lượng ổ cứng.
- **Bật/Tắt tính năng (Feature Flags):** Cho phép tính năng mới chạy ẩn ở Sandbox trước khi mở cho khách hàng thật.

### 1.2. Mối quan hệ giữa Deployment và Service
- **Deployment ("Xưởng sản xuất"):** Quản lý các Pods (Container). Nó chịu trách nhiệm giữ cho ứng dụng luôn chạy đúng số lượng (`replicas`), tự động đẻ Pod mới nếu Pod cũ chết (Self-healing). Nó dùng `selector.matchLabels` để đếm số lượng Pod nó đang quản lý.
- **Service ("Cổng giao dịch"):** Pods thay đổi IP liên tục khi bị khởi động lại. Service cung cấp một IP và tên miền nội bộ tĩnh (không đổi) để các ứng dụng khác kết nối vào. Sau đó Service làm nhiệm vụ Load Balancer, tản đều lượng truy cập xuống các Pods sống đang được gắn nhãn tương ứng.

### 1.3. Biến `{{ .Values }}` và `{{ .Chart }}` lấy từ đâu ra?
Kubernetes không hiểu cú pháp `{{ }}`. Đây là "ma thuật" của **Helm (Go Template Engine)**:
1. Helm nạp file `Chart.yaml` vào bộ nhớ tạo thành đối tượng `.Chart`.
2. Helm nạp file `values.yaml` (và hợp nhất với `values-sandbox.yaml`) tạo thành đối tượng `.Values`.
3. Helm đi vào thư mục `templates/`, tìm các dấu `{{ }}` và gán chữ tương ứng vào.
4. Cuối cùng, sinh ra file YAML thuần túy 100% rồi mới nộp cho Kubernetes deploy.

### 1.4. Thiết kế Microservices bằng Helm (Chia để trị)
Nếu có nhiều ứng dụng (BE, FE, Worker), phương pháp chuẩn mực nhất là **tạo nhiều thư mục Helm Chart độc lập** (`components/backend`, `components/frontend`). 
Điều này giúp vòng đời CI/CD của từng dịch vụ tách biệt hoàn toàn, không sợ deploy ứng dụng này lại làm hỏng cấu hình của ứng dụng kia.

---

## 2. Kiến trúc ArgoCD & GitOps

### 2.1. Hạ tầng nền tảng (Foundation) & Sync Waves
- **Foundation** là những thứ dùng chung cho toàn cluster: Namespaces, External Secrets (kho mật khẩu), RBAC, NetworkPolicies.
- **Sync Waves** (Làn sóng đồng bộ): ArgoCD tuân thủ thứ tự chạy ưu tiên. 
  - `Wave 0`: Đọc file `00-foundation.yaml`, chạy đi xây móng (tạo namespace, kết nối AWS Secrets). 
  - `Wave 1`: Đọc file `01-backend.yaml` để deploy ứng dụng. Nếu không có móng (Wave 0), ứng dụng (Wave 1) sẽ sập ngay lập tức vì không tìm thấy Namespace.

### 2.2. Tại sao lại đánh số tên file (`00-`, `01-`)?
Mặc dù ArgoCD không quan tâm tên file, việc đánh số là Best Practice nhằm:
- Giúp con người (DevOps) nhìn vào là biết ngay thứ tự phụ thuộc (Cái 00 quan trọng hơn cái 01).
- Trùng khớp với logic của `Sync Wave`.
- Đề phòng khi Kỹ sư chạy tay bằng lệnh `kubectl apply -f folder/`, Kubernetes sẽ đọc theo thứ tự bảng chữ cái nên sẽ apply Foundation trước Backend, không gây lỗi rác.

### 2.3. AppProject (`tf1-project`) có vai trò gì?
`AppProject` là "Trạm kiểm lâm" bảo mật của ArgoCD:
- **`sourceRepos`**: Ngăn chặn lấy source code bậy bạ ngoài Internet, chỉ cho phép kéo code từ kho Git của công ty.
- **`destinations`**: Giới hạn việc deploy chỉ được nằm trong cụm K8s nội bộ và những namespace nhất định.
- **`clusterResourceWhitelist`**: Cho phép đẻ ra các tài nguyên cấp Cluster (như `Namespace` hoặc `ClusterRole`). Nếu không có dòng `group: "*", kind: "*"`, ArgoCD sẽ chặn đứng cụm Foundation vì sợ đụng chạm đến rễ của hệ thống.

---

## 3. Kubernetes Networking & Security

### 3.1. NetworkPolicy vs Ingress
Hai khái niệm này hoàn toàn khác nhau:
- **Ingress**: "Bác bảo vệ cổng chính". Hứng traffic từ ngoài Internet, giải mã SSL, đọc tên miền (ví dụ: `api.triagehub.com`) rồi dắt tay khách hàng vào đúng ứng dụng.
- **NetworkPolicy**: "Tường lửa nội bộ". Chặn các ứng dụng bên trong K8s âm thầm giao tiếp chui với nhau.

### 3.2. Sức mạnh của Default Deny NetworkPolicy
Luật `default-deny-all` sẽ chặn đứng MỌI kết nối (Cả Vào và Ra) đối với toàn bộ Pods trong một Namespace.
- Mức độ chặn là ở **cấp độ Pod**, thông qua giao diện mạng ảo (CNI).
- **Kết quả cực đoan nhưng an toàn:** Dù 2 Pods (Backend và Database) có nằm trên cùng 1 con Server vật lý (Worker Node), chúng vẫn **KHÔNG THỂ** gửi tin nhắn cho nhau vì hệ điều hành Linux Kernel đã chặt đứt kết nối ngay tại cửa ngõ của Pod.
- Từ luật chặn sạch này, kỹ sư DevOps sẽ từ từ đục những "lỗ hổng" siêu nhỏ (Allow list) chỉ đủ để các Pods cần thiết gọi được nhau, triệt tiêu hoàn toàn đường đi của Hacker nếu lỡ xâm nhập được 1 Pod.
