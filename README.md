# my-devops

로컬 쿠버네티스 GitOps 데모. `app/` 을 고치면 배포까지 자동으로 굴러갑니다.

## 루프

```
app/index.html 수정
  → git push
  → GitHub Actions: 이미지 빌드 → GHCR push
  → Actions가 chart/values-dev.yaml 의 image.tag 커밋
  → ArgoCD가 폴링으로 감지 (최대 3분)
  → dev 네임스페이스 sync
  → http://localhost:30080

prod는 이 루프에 없습니다. 손으로 승격합니다 (아래 참고).
```

측정된 실제 소요시간: push부터 반영까지 **약 170초** (CI 24초 + ArgoCD 폴링 대기).

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

브라우저에서 자체서명 인증서 경고가 뜹니다. 로컬이라 무시하고 진행하면 됩니다.

## 자주 쓰는 명령

```bash
# 3분 기다리기 싫을 때 즉시 sync
kubectl patch app web-dev -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# prod 배포 (automated 가 없어서 직접 눌러야 합니다)
# syncOptions 를 operation 에 같이 안 넣으면 namespaces "prod" not found 로 실패합니다.
# syncPolicy.syncOptions 는 자동 sync 에만 적용됩니다.
kubectl patch app web-prod -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"v1.0.0","syncOptions":["CreateNamespace=true"]}}}'

# 상태 확인
kubectl get app -n argocd
kubectl get pods -n dev
kubectl get pods -n prod

# 컨텍스트 확인 — 회사 EKS와 섞이지 않게 항상 체크
kubectl config current-context   # docker-desktop 이어야 함
```

## 구조

```
app/          정적 페이지 + Dockerfile  (여기를 고치면 루프 발동)
chart/        Helm 차트. ArgoCD가 감시하는 대상. 차트는 한 벌, 환경별로 values 만 다름
  values.yaml       공통 (image.repo, resources)
  values-dev.yaml   CI가 image.tag 를 자동 갱신
  values-prod.yaml  손으로 승격
argocd/       Application CR 두 벌. chart/ 를 가리킴 (일부러 분리 — 아래 참고)
  app-dev.yaml   targetRevision: main    → ns dev,  automated
  app-prod.yaml  targetRevision: v1.0.0  → ns prod, 수동 sync
```

`argocd/` 가 `chart/` 밖에 있는 이유: 안에 두면 helm 이 이 파일까지
렌더링해서 ArgoCD가 자기 자신을 `default` 네임스페이스에 만들려다 깨집니다.

helm 릴리스 이름은 Application 의 `metadata.name`(`web`)이 됩니다. 템플릿의
`{{ .Release.Name }}` 이 그 값이라 리소스 이름은 예전 `manifests/` 시절과 같습니다.

## 알아둘 것

- **CI 무한루프 방지**: 워크플로가 `chart/` 를 커밋하는데, 트리거가 `paths: app/**`
  로 제한돼 있어 그 커밋이 자신을 다시 부르지 않습니다. 이 필터를 지우면 무한루프입니다.
- **GHCR 소문자**: `github.repository` 는 `Nakyungwon/...` 이라 대문자가 섞입니다.
  GHCR은 소문자만 받으므로 워크플로에서 `IMAGE` 를 소문자로 하드코딩했습니다.
- **selfHeal 켜져 있음(dev만)**: `kubectl edit` 로 직접 바꿔도 git 상태로 되돌아갑니다.
  수동 변경을 테스트하려면 `syncPolicy.automated.selfHeal` 을 꺼야 합니다.
  prod 는 `automated` 자체가 없어서 해당 없습니다.
- **NodePort 는 클러스터 전역**: 네임스페이스로 안 갈립니다. dev 30080 / prod 30081 이
  겹치면 나중에 뜨는 쪽이 `provided port is already allocated` 로 실패합니다.
- **valueFiles 쓰면 values.yaml 기본 포함이 꺼집니다**: Application 에 `values.yaml` 을
  명시적으로 같이 나열해야 공통값이 들어갑니다.
- **prod 승격 절차**: `chart/values-prod.yaml` 의 `tag:` 를 새 SHA 로 → 커밋 →
  `git tag vX.Y.Z && git push --tags` → `argocd/app-prod.yaml` 의 `targetRevision`
  갱신 후 apply. CI 는 prod 를 절대 건드리지 않습니다.
- **k8s 1.25 고정**: Docker Desktop 4.15 내장 버전입니다. ArgoCD도 여기 맞춰
  `v2.9.3` 으로 핀을 걸었습니다. 최신 ArgoCD는 1.27+ 를 요구해서 안 올라갑니다.
  회사 EKS(1.33)와는 버전 차이가 있으니 prod 매니페스트 검증용으로는 쓰지 마세요.

## 재구축

클러스터를 날렸다가 다시 만들 때:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml # apt install argocd
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
# kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
        # └──┬─┘ └─────────┬────────┘ └┬─┘ └─┬─┘ └───┬──┘ └─────┬────┘
        #  기다려     이 조건이 참될때까지   뭘    전부     어디서     최대 5분
kubectl apply -f argocd/app-dev.yaml -f argocd/app-prod.yaml
```
