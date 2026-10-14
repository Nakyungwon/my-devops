# my-devops

로컬 쿠버네티스 GitOps 데모의 **코드 리포**. `app/` 을 고치면 배포까지 자동으로 굴러갑니다.
배포 설정(Helm 차트, ArgoCD Application)은 [my-devops-config](https://github.com/Nakyungwon/my-devops-config) 에 있고,
ArgoCD 는 그 리포만 봅니다.

## 루프

```
app/index.html 수정 → develop push
  → ci-dev: 이미지 빌드 → GHCR push
  → my-devops-config 의 chart/values-dev.yaml image.tag 커밋 (deploy key)
  → ArgoCD dev 자동 sync
  → http://localhost:30080

develop → main merge
  → ci-prod: dev 태그를 my-devops-config 의 values-prod.yaml 에 복사 커밋
  → ArgoCD prod 는 OutOfSync 로 대기, 사람이 SYNC
  → http://localhost:30081
```

## 구조

```
app/                         정적 페이지 + Dockerfile (여기를 고치면 루프 발동)
.github/workflows/ci-dev.yml   develop: 빌드 + 설정 리포 dev 태그 갱신 + 즉시 refresh(self-hosted)
.github/workflows/ci-prod.yml  main: 설정 리포 prod 태그 승격 (빌드 없음)
.github/actions/bump-tag/      설정 리포 values 파일 태그 sed + 커밋 + push
```

## 접속

| 대상      | 주소                                            |
| --------- | ----------------------------------------------- |
| 앱 (dev)  | http://localhost:30080                          |
| 앱 (prod) | http://localhost:30081                          |
| ArgoCD UI | https://localhost:8081 (아래 port-forward 필요) |

```bash
# 8080은 Docker Desktop이 쓰고 있어서 8081로 뺍니다.
kubectl port-forward -n argocd svc/argocd-server 8081:443
# id: admin
# pw: kubectl -n argocd get secret argocd-initial-admin-secret \
#       -o jsonpath='{.data.password}' | base64 -d
```

prod 배포·롤백·재구축 명령은 my-devops-config README 에 있습니다.

## 알아둘 것

- **설정 리포 쓰기 권한**: CI 는 `GITHUB_TOKEN` 이 아니라 deploy key 로 my-devops-config 에 push 합니다.
  비밀키는 이 리포 시크릿 `CONFIG_REPO_DEPLOY_KEY`, 공개키는 설정 리포 Deploy keys(쓰기 허용).
  키를 갈려면 둘 다 바꿔야 합니다.
- **paths 필터**: 태그 커밋이 설정 리포로 가므로 무한루프 걱정은 없습니다. 필터는 "app/ 이 바뀔 때만 빌드"
  용도로 남아 있습니다.
- **GHCR 소문자**: `github.repository` 는 `Nakyungwon/...` 이라 대문자가 섞입니다.
  GHCR은 소문자만 받으므로 워크플로에서 `IMAGE` 를 소문자로 하드코딩했습니다.
  설정 리포 `chart/values.yaml` 의 `image.repo` 와 손으로 맞춰야 합니다.
- **k8s 1.25 고정**: Docker Desktop 4.15 내장 버전입니다. ArgoCD 는 `v2.9.3` 이 떠 있습니다.
  회사 EKS(1.33)와는 버전 차이가 있으니 prod 매니페스트 검증용으로는 쓰지 마세요.

```bash
# 컨텍스트 확인 — 회사 EKS와 섞이지 않게 항상 체크
kubectl config current-context   # docker-desktop 이어야 함
```
