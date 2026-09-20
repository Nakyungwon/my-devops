#!/usr/bin/env bash
# ArgoCD 부트스트랩. 클러스터당 한 번만 손으로 실행하는 "마지막 수동 계층".
# 이 위(앱 배포)는 전부 argocd/app-*.yaml 이 GitOps 로 관리한다.
#
# 사용법:  ./bootstrap/install.sh
# 재실행:  안전하다. 이미 깔려 있으면 그냥 최신 상태로 맞춘다 (idempotent).

# set: 스크립트를 안전하게 죽이는 옵션 3개.
#   -e         명령 하나라도 실패하면 즉시 중단 (에러 무시하고 계속 진행 방지)
#   -u         선언 안 한 변수 쓰면 에러 (오타로 빈값 들어가는 사고 방지)
#   -o pipefail  파이프(|) 중간 명령이 실패해도 전체를 실패로 처리
set -euo pipefail

# 설치할 ArgoCD 버전을 변수로 고정. 업그레이드는 이 한 줄만 바꿔서 재실행.
# stable 로 두면 "언제 깔았냐"에 따라 클러스터마다 버전이 달라진다.
ARGOCD_VERSION="v2.13.2"
# 위 버전에 해당하는 공식 설치 매니페스트 URL 을 조립. ${VAR} 로 버전이 끼워짐.
MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# 화면에 진행 상황 출력 (>> 는 그냥 눈에 띄라고 붙인 표시).
echo ">> namespace argocd"
# argocd 네임스페이스 생성.
#   --dry-run=client -o yaml : 실제로 만들지 말고 "만들 YAML"만 출력
#   | kubectl apply -f -      : 그 YAML 을 apply 로 적용
# 이렇게 하면 이미 있어도 에러 안 나고 넘어감 (create 만 쓰면 "이미 있음" 에러).
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo ">> install argocd ${ARGOCD_VERSION}"
# ArgoCD 본체 설치. 위 URL 의 매니페스트를 argocd 네임스페이스에 적용.
#   -n argocd : 대상 네임스페이스
#   -f URL    : 원격 파일을 그대로 적용 (Deployment, Service, CRD 등 전부 포함)
# apply 라서 재실행하면 바뀐 부분만 갱신 = 업그레이드로 동작.
kubectl apply -n argocd -f "${MANIFEST}"

echo ">> wait for argocd-server"
# argocd-server 파드가 다 뜰 때까지 대기 (안 기다리면 다음 단계에서 비번 조회 실패).
#   rollout status : 롤아웃이 끝날 때까지 블로킹
#   --timeout=180s : 3분 넘으면 실패 처리하고 중단
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

echo ">> register applications (argocd/*.yaml)"
# 이 repo 의 argocd/ 폴더 전체를 apply → app-dev / app-prod Application 등록.
#   $(dirname "$0")     : 이 스크립트가 있는 폴더 (bootstrap/)
#   /../argocd/         : 거기서 한 칸 위로 올라가 argocd/ 폴더 지정
# 어느 위치에서 실행하든 경로가 맞도록 스크립트 기준 상대경로로 계산.
kubectl apply -f "$(dirname "$0")/../argocd/"

# 빈 줄 하나 (출력 보기 좋으라고).
echo
echo "==== ArgoCD 준비 완료 ===="
# UI 접속 방법 안내 (실제 실행이 아니라 그냥 알려주는 문자열).
echo "UI:  kubectl -n argocd port-forward svc/argocd-server 8081:443"
echo "     -> https://localhost:8081   (id: admin)"
# 다음 줄에 비번을 이어 붙이려고 -n 으로 줄바꿈 없이 "pw:  " 만 출력.
echo -n "pw:  "
# 초기 admin 비밀번호 꺼내기. ArgoCD 가 만든 시크릿에서 password 필드를 읽음.
#   get secret ... -o jsonpath='{.data.password}' : 그 값만 추출 (base64 로 인코딩돼 있음)
#   | base64 -d                                   : 사람이 읽을 수 있게 디코드
#   ; echo                                        : 마지막에 줄바꿈 하나 추가
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
