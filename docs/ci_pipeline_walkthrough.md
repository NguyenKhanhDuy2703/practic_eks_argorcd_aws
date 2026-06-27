# Phân tích chi tiết CI/CD Pipeline (GitHub Actions)

Tài liệu này giải thích chi tiết các workflow GitHub Actions cho dự án, giúp bạn hiểu rõ từng bước tự động hóa khi có code mới được đẩy lên repository.

Chúng ta sẽ có 2 workflow chính:
1. **Application CI Pipeline**: Chạy test, quét bảo mật (Trivy), build Docker image và đẩy lên ECR.
2. **Terraform CI Pipeline**: Tự động chạy `terraform plan` và `apply` khi thay đổi hạ tầng.

---

## 1. Application CI Pipeline (`.github/workflows/ci-build-test.yml`)

Workflow này tự động chạy khi bạn tạo Pull Request hoặc push code vào nhánh `main`, `develop`.

```yaml
name: CI/CD Pipeline - Application

on:
  push:
    branches: [ "main", "develop" ]
  pull_request:
    branches: [ "main", "develop" ]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: tf1/ai-engine

# Yêu cầu quyền cần thiết để sử dụng OIDC (bảo mật, không dùng static AWS_ACCESS_KEY_ID)
permissions:
  id-token: write
  contents: read

jobs:
  build-and-test:
    name: Build, Test & Scan
    runs-on: ubuntu-latest

    steps:
    - name: Checkout Code
      uses: actions/checkout@v3

    # 1. Quét Secret trước tiên (Tránh lộ key AWS/Jira)
    - name: Gitleaks Secret Scan
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

    # 2. Xác thực với AWS qua OIDC
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        role-to-assume: arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole
        aws-region: ${{ env.AWS_REGION }}

    # 3. Đăng nhập vào Amazon ECR
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1

    # 4. Chạy Unit Test (Ví dụ cho Python)
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.12'
    - name: Run Tests
      run: |
        pip install pytest
        pytest ./tests/

    # 5. Build Docker Image (Chỉ build, chưa push)
    - name: Build Docker Image
      env:
        REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        
    # 6. Quét lỗ hổng (Vulnerabilities) trên Image vừa build bằng Trivy
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: '${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}'
        format: 'table'
        exit-code: '1' # Sẽ dừng CI nếu phát hiện lỗi CRITICAL
        ignore-unfixed: true
        vuln-type: 'os,library'
        severity: 'CRITICAL,HIGH'

    # 7. Push Image lên ECR (Chỉ khi merge hoặc push lên branch chính)
    - name: Push Image to ECR
      if: github.event_name == 'push'
      env:
        REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker push $REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

    # 8. Cập nhật Kustomize Image tag để trigger ArgoCD Deploy
    - name: Update ArgoCD Manifests
      if: github.event_name == 'push'
      run: |
        # Script để đổi giá trị image tag trong file kustomization.yaml
        cd config-repo/overlays/sandbox
        kustomize edit set image tf1-ai-engine=$REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        git commit -am "Update image to ${{ github.sha }}"
        git push origin main
```

**Giải thích chi tiết:**
- `permissions: id-token: write`: Rất quan trọng! Cho phép GitHub Action lấy token OIDC để đổi lấy `Temporary Credentials` từ AWS IAM Role (`GitHubActionsRole`), loại bỏ hoàn toàn rủi ro lộ secret (như `AWS_SECRET_ACCESS_KEY`).
- Bước **Gitleaks**: Quét toàn bộ code vừa commit xem có lỡ push password/token nào lên không. Nếu có, CI sẽ `Failed` ngay lập tức.
- Bước **Run Trivy**: Quét Docker Image vừa build. Cờ `exit-code: '1'` và `severity: 'CRITICAL,HIGH'` nghĩa là nếu có bất kỳ lỗ hổng bảo mật mức độ Nghiêm trọng/Cao nào, pipeline sẽ báo đỏ và chặn không cho deploy.
- Bước **Update ArgoCD Manifests**: Đây là phần lõi của GitOps. GitHub Action không tự deploy lên K8s. Nó chỉ sửa lại Image Tag trong file YAML ở một repo khác (Config Repo). Sau đó, **ArgoCD** (bên trong EKS cluster) sẽ tự động phát hiện thay đổi trên Git và tiến hành Pull cấu hình mới về để deploy.

---

## 2. Infrastructure CI Pipeline (`.github/workflows/ci-terraform.yml`)

Workflow này theo dõi thư mục `tf1-triage-hub/tf/`.

```yaml
name: CI/CD Pipeline - Terraform

on:
  pull_request:
    paths:
      - 'tf1-triage-hub/tf/**'
  push:
    branches: [ "main", "develop" ]
    paths:
      - 'tf1-triage-hub/tf/**'

permissions:
  id-token: write
  contents: read
  pull-requests: write # Để comment kết quả terraform plan vào PR

jobs:
  terraform-plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    
    steps:
    - name: Checkout Code
      uses: actions/checkout@v3

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        role-to-assume: arn:aws:iam::ACCOUNT_ID:role/TerraformDeployRole
        aws-region: us-east-1

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.8.0

    - name: Terraform Init
      run: terraform init
      working-directory: tf1-triage-hub/tf/environments/sandbox

    - name: Terraform Format
      run: terraform fmt -check
      working-directory: tf1-triage-hub/tf

    - name: Terraform Validate
      run: terraform validate
      working-directory: tf1-triage-hub/tf/environments/sandbox

    - name: Terraform Plan
      id: plan
      run: terraform plan -no-color
      working-directory: tf1-triage-hub/tf/environments/sandbox

    # Đẩy output của `terraform plan` lên comment của PR để dễ review
    - name: Update Pull Request
      uses: actions/github-script@v6
      env:
        PLAN: "terraform\n${{ steps.plan.outputs.stdout }}"
      with:
        github-token: ${{ secrets.GITHUB_TOKEN }}
        script: |
          const output = `#### Terraform Plan 📖
          
          <details><summary>Show Plan</summary>
          
          \`\`\`\n
          ${process.env.PLAN}
          \`\`\`
          
          </details>`;
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: output
          })

  terraform-apply:
    name: Terraform Apply
    runs-on: ubuntu-latest
    # Chỉ chạy khi Merge PR vào main/develop
    if: github.event_name == 'push' 
    
    steps:
    - name: Checkout Code
      uses: actions/checkout@v3

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        role-to-assume: arn:aws:iam::ACCOUNT_ID:role/TerraformDeployRole
        aws-region: us-east-1

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2

    - name: Terraform Init
      run: terraform init
      working-directory: tf1-triage-hub/tf/environments/sandbox

    - name: Terraform Apply
      run: terraform apply -auto-approve
      working-directory: tf1-triage-hub/tf/environments/sandbox
```

**Giải thích chi tiết:**
- `paths: ['tf1-triage-hub/tf/**']`: Giúp tiết kiệm chi phí chạy CI. Action này CHỈ chạy khi có ai đó sửa code hạ tầng Terraform. Nếu sửa code app, nó sẽ không chạy.
- Job **terraform-plan**: Chạy khi bạn mở PR. Tính năng thú vị nhất là bước `Update Pull Request` sử dụng `github-script`. Nó sẽ lấy output của lệnh `terraform plan` và tự động post thành một comment trên PR của bạn. Người review sẽ thấy rõ hạ tầng chuẩn bị thay đổi những gì mà không cần phải chạy code trên máy local.
- Job **terraform-apply**: Chạy khi PR được Merge. Bước `terraform apply -auto-approve` sẽ tự động triển khai hạ tầng thật trên AWS.
