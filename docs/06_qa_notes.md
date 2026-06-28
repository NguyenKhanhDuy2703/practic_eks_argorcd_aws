# 📝 Sổ tay Q&A và Ghi chú kỹ thuật (ArgoCD & GitOps)

Tài liệu này tổng hợp lại các câu hỏi, thắc mắc và những khái niệm chuyên sâu đã được phân tích trong quá trình xây dựng hệ thống ArgoCD.

---

### Q1: Tại sao `00-foundation.yaml` đọc được Constraint/Template của Gatekeeper còn `00-gatekeeper.yaml` thì không?
- **Sự khác biệt về Source (Nguồn):**
  - File `00-gatekeeper.yaml` trỏ `repoURL` ra ngoài internet (`https://open-policy-agent.github.io/gatekeeper/charts`). Nó có nhiệm vụ tải và cài đặt phần lõi của phần mềm Gatekeeper (Core Controller & CRDs). Nó không hề biết dự án của bạn có những luật (policies) gì.
  - File `00-foundation.yaml` trỏ `repoURL` vào chính kho Git của dự án này, và `path` là thư mục `cd/components/foundation`. ArgoCD có tính năng quét đệ quy (recursive), nó sẽ tự động chui vào tất cả thư mục con (bao gồm `admission-policies/`) để tìm và apply các file YAML của Constraint/Template.

### Q2: Tại sao phải vất vả tạo `tf1-project` mà không xài luôn project `default` của ArgoCD?
- **Khái niệm AppProject:** Trong ArgoCD, Project đóng vai trò như một "Hàng rào bảo vệ" (Security Boundaries / Guardrails).
- Khi bạn cài ArgoCD, mặc định luôn có một project tên là `default`. Project này có đặc quyền "Super Admin", tức là cho phép mọi Application kéo code từ mọi nơi, và deploy vào bất kỳ cụm/namespace nào.
- Dùng `default` cho Minikube cá nhân thì nhanh, nhưng trên EKS thực tế thì rất nguy hiểm.
- Do đó, ta tạo ra **`tf1-project`** để giới hạn chặt chẽ (RBAC):
  1. Chỉ được phép kéo code từ 3-4 repo Git/Helm an toàn (`sourceRepos`).
  2. Chỉ được phép deploy vào các namespace cụ thể được cho phép trước (`destinations`).

### Q3: Tính năng tự tạo Namespace (`CreateNamespace=true`) hoạt động ra sao nếu không cấu hình trước?
- Bạn không cần phải chạy lệnh `kubectl create namespace` bằng tay.
- Khi tạo Application, thêm `syncOptions: - CreateNamespace=true` thì ArgoCD sẽ tự tạo namespace nếu chưa có.
- Tuy nhiên, ArgoCD vẫn phải "xin phép" `AppProject`. Nếu namespace đó không nằm trong mục `destinations` của `tf1-project`, ArgoCD sẽ từ chối tạo. Do đó, bạn phải khai báo đầy đủ các namespace hợp lệ vào `tf1-project.yaml`.

### Q4: `clusterResourceWhitelist` là gì và tại sao lại quan trọng?
Trong Kubernetes có 2 loại tài nguyên:
1. **Namespace-scoped**: (Pod, Service...) giới hạn trong 1 namespace.
2. **Cluster-scoped**: (Namespace, CRD, ClusterRole...) tác động toàn cụm.

Custom AppProject mặc định sẽ **cấm** tạo toàn bộ tài nguyên cấp cụm (Cluster-scoped). `clusterResourceWhitelist` là "chìa khóa" mở cổng cấp quyền.
- Để ArgoCD tự tạo được Namespace (như Q3), phải có ít nhất `kind: "Namespace"`.
- Vì các phần mềm nền tảng (Gatekeeper, Prometheus, ESO...) khi cài bằng Helm luôn sinh ra các tài nguyên hệ thống (CRD, ClusterRoles), nếu bạn khóa chức năng này, tiến trình cài đặt sẽ báo lỗi ngay lập tức.
- Lời khuyên cho project đóng vai trò làm Platform: Mở khóa bằng cấu hình:
  ```yaml
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  ```
  Hoặc phải khai báo chi tiết từng loại (`ClusterRole`, `CustomResourceDefinition`...) nếu bạn muốn siết chặt tuyệt đối.

### Q5: Tại sao tạo EKS phải tạo "Node Group" và không thấy cấu hình EC2 ở đâu?
Kiến trúc của EKS (và Kubernetes nói chung) luôn chia làm 2 phần tách biệt:
1. **Control Plane (Bộ não trung tâm):** Nơi chứa API Server, etcd, Scheduler. Trên EKS, AWS quản lý 100% phần này (bạn không được truy cập vào server của nó). Trong Terraform, nó chính là resource `aws_eks_cluster`.
2. **Data Plane (Tay chân):** Là các máy chủ (worker nodes) nơi các Pod (ứng dụng của bạn) thực sự chạy và tiêu tốn CPU/RAM.

**Tại sao không thấy khai báo cấu hình EC2 thuần túy (`aws_instance`)?**
Bởi vì trong source code, chúng ta đang sử dụng tính năng **Managed Node Group (MNG)** của AWS thông qua resource `aws_eks_node_group`.
- Nếu tự làm, bạn phải tự viết code tạo EC2, tự cài containerd, tự cấu hình bảo mật, và tự viết bash script chạy lúc khởi động (`user_data`) để ép EC2 đó join vào cụm EKS. Cực kỳ vất vả!
- Khi dùng Managed Node Group, bạn chỉ cần ném cho AWS cấu hình đơn giản: `instance_types = ["t3.medium"]` và `scaling_config` (cần 2 máy, tối đa 4 máy). AWS sẽ **ngầm tự động** sinh ra một Auto Scaling Group (ASG), tự động đẻ ra các máy EC2 dùng hệ điều hành chuyên dụng (Amazon Linux 2 EKS Optimized AMI), và tự lo luôn việc kết nối chúng vào cluster của bạn một cách hoàn hảo.

**Vậy tự tạo EC2 bằng tay (Self-managed nodes) được không?**
Hoàn toàn được! Các hệ thống cũ hoặc có yêu cầu custom HĐH cực kỳ đặc biệt mới dùng cách này. Nhưng ngày nay, 99% các dự án thực tế đều dùng Managed Node Group (như code của bạn) để ủy thác việc bảo trì, vá lỗi HĐH và nâng cấp phiên bản Kubernetes cho AWS lo, giúp kỹ sư DevOps "nhàn" đi rất nhiều.
