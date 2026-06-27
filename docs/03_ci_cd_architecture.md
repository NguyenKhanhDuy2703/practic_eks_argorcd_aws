# Tổng quan Kiến trúc CI/CD & Progressive Delivery

Tài liệu này tổng hợp toàn bộ luồng luân chuyển mã nguồn từ lúc lập trình viên Push code cho đến khi tới tay người dùng cuối, áp dụng đầy đủ các tiêu chuẩn DevSecOps và Zero-Downtime Deployment.

---

## 1. Sơ đồ Luồng Hoạt Động (Overview Flow)

```mermaid
graph TD
    subgraph "CI: GitHub Actions (DevSecOps)"
        A[Developer Push Code] -->|Trigger| B[ci-main.yml]
        B --> C[reusable-test.yml]
        C -->|Pass| D[reusable-build-sign.yml]
        D -->|1. Build| D1[Docker Image]
        D -->|2. Quét| D2[Trivy Scanner]
        D2 -->|Fail| Z[Pipeline Bị Hủy]
        D2 -->|Pass| D3[Push lên GHCR]
        D3 -->|3. Ký số| D4[Cosign Keyless]
        D4 --> E[reusable-update-gitops.yml]
        E -->|Cập nhật tag| F[values-sandbox.yaml]
    end

    subgraph "CD: ArgoCD & Argo Rollouts"
        F -->|Git Webhook| G((ArgoCD Server))
        G -->|Đọc file| H[tf1-backend-sandbox]
        
        H -->|Tạo Rollout| I[Argo Rollouts Controller]
        I -->|Canary 25%| J1[Bản Mới 25%]
        I -->|Pause 30s| J2[Chờ Phản Hồi]
        J2 -->|Canary 50%| J3[Bản Mới 50%]
        J3 -->|Pause 30s| J4[Chờ Phản Hồi]
        J4 -->|Canary 75%| J5[Bản Mới 75%]
        J5 -->|Pause 30s| J6[Chờ Phản Hồi]
        J6 -->|Hoàn thành| J7[Bản Mới 100%]
    end

    classDef ci fill:#24292e,stroke:#fff,stroke-width:2px,color:#fff;
    classDef cd fill:#ef7b4d,stroke:#fff,stroke-width:2px,color:#fff;
    
    class A,B,C,D,E,F ci;
    class G,H,I,J1,J2,J3,J4,J5,J6,J7 cd;
```

---

## 2. Kiến trúc CI (Mô hình Modular Workflows)

Thay vì một file CI khổng lồ, dự án áp dụng mô hình **Reusable Workflows** để dễ dàng bảo trì và mở rộng:

1. **`ci-main.yml`**: Trái tim điều phối. Kích hoạt khi có thay đổi trong thư mục `app/`. Gọi tuần tự các file con.
2. **`reusable-test.yml`**: Chạy Unit Test và Lint (cú pháp). Cắt đứt pipeline nếu code dỏm.
3. **`reusable-build-sign.yml`**:
   - **Trivy:** Quét mã độc trong thư viện HĐH và ngôn ngữ.
   - **GHCR:** Lưu trữ Image miễn phí không giới hạn.
   - **Cosign Keyless:** Sử dụng OIDC Token của Github để ký điện tử (Chứng thực nguồn gốc) mà không cần rủi ro lưu trữ Private Key.
4. **`reusable-update-gitops.yml`**: Dùng `sed` cập nhật image tag trong `values-sandbox.yaml` và tự động Commit.

---

## 3. Kiến trúc CD (App of Apps & Multiple Sources)

Mọi thứ trong K8s được khai báo (Declarative) ở thư mục `tf1-triage-hub/cd/`.

- **Lệnh Bootstrap Duy Nhất:** `kubectl apply -f bootstrap.yaml`. Từ đây, ArgoCD sẽ tự đẻ ra các tài nguyên khác.
- **Wave 0 (Nền móng):** `00-foundation`, `00-gatekeeper` (Bảo vệ K8s bằng luật OPA), và `00-rollouts` (Cài đặt Argo Rollouts Controller).
- **Wave 1 (Ứng dụng):** `01-backend`. Triển khai Backend.

---

## 4. Progressive Delivery (Triển khai Nhỏ Giọt)

Ứng dụng Backend không còn dùng K8s Deployment thông thường mà đã được nâng cấp lên **Rollout Custom Resource**.

### Chiến lược được sử dụng: Canary (25-50-75-100)
- Bước 1: 25% traffic vào bản mới (Chờ 30 giây)
- Bước 2: 50% traffic vào bản mới (Chờ 30 giây)
- Bước 3: 75% traffic vào bản mới (Chờ 30 giây)
- Bước 4: 100% traffic (Bản cũ bị hủy đi).

**Ưu điểm:** Nếu bước 25% bị Crash (sập), Argo Rollouts sẽ tự động ngừng lại và trả traffic về bản cũ. Giúp người dùng hoàn toàn không cảm nhận được lỗi, đạt chuẩn **Zero Downtime**.
