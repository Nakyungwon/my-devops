# my-devops

로컬 쿠버네티스 GitOps 데모. `app/` 을 고치면 배포까지 자동으로 굴러갑니다.

## 루프

```
app/index.html 수정
  → git push
  → GitHub Actions: 이미지 빌드 → GHCR push
  → Actions가 manifests/deployment.yaml 태그 커밋
  → ArgoCD가 폴링으로 감지 (최대 3분)
  → 클러스터 sync
  → http://localhost:30080
```

측정된 실제 소요시간: push부터 반영까지 **약 170초** (CI 24초 + ArgoCD 폴링 대기).

## 접속

| 대상 | 주소 |
|---|---|
| 앱 | http://localhost:30080 |
| ArgoCD UI | https://localhost:8080 (아래 port-forward 필요) |

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# id: admin
# pw: kubectl -n argocd get secret argocd-initial-admin-secret \
#       -o jsonpath='{.data.password}' | base64 -d
```

브라우저에서 자체서명 인증서 경고가 뜹니다. 로컬이라 무시하고 진행하면 됩니다.

## 자주 쓰는 명령

```bash
# 3분 기다리기 싫을 때 즉시 sync
kubectl patch app web -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 상태 확인
kubectl get app -n argocd
kubectl get pods -l app=web

# 컨텍스트 확인 — 회사 EKS와 섞이지 않게 항상 체크
kubectl config current-context   # docker-desktop 이어야 함
```

## 구조

```
app/          정적 페이지 + Dockerfile  (여기를 고치면 루프 발동)
manifests/    ArgoCD가 감시하는 대상. CI가 image 태그를 자동 갱신
argocd/       Application CR. manifests/ 를 가리킴 (일부러 분리 — 아래 참고)
```

`argocd/application.yaml` 이 `manifests/` 밖에 있는 이유: 안에 두면 ArgoCD가
자기 자신을 `default` 네임스페이스에 만들려고 시도해서 깨집니다.

## 알아둘 것

- **CI 무한루프 방지**: 워크플로가 `manifests/` 를 커밋하는데, 트리거가 `paths: app/**`
  로 제한돼 있어 그 커밋이 자신을 다시 부르지 않습니다. 이 필터를 지우면 무한루프입니다.
- **GHCR 소문자**: `github.repository` 는 `Nakyungwon/...` 이라 대문자가 섞입니다.
  GHCR은 소문자만 받으므로 워크플로에서 `IMAGE` 를 소문자로 하드코딩했습니다.
- **selfHeal 켜져 있음**: `kubectl edit` 로 직접 바꿔도 git 상태로 되돌아갑니다.
  수동 변경을 테스트하려면 `syncPolicy.automated.selfHeal` 을 꺼야 합니다.
- **k8s 1.25 고정**: Docker Desktop 4.15 내장 버전입니다. ArgoCD도 여기 맞춰
  `v2.9.3` 으로 핀을 걸었습니다. 최신 ArgoCD는 1.27+ 를 요구해서 안 올라갑니다.
  회사 EKS(1.33)와는 버전 차이가 있으니 prod 매니페스트 검증용으로는 쓰지 마세요.

## 재구축

클러스터를 날렸다가 다시 만들 때:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
kubectl apply -f argocd/application.yaml
```
