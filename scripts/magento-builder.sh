#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "用法: $0 <namespace> <release> <php-image:tag> [job-suffix]" >&2
  exit 1
fi

NAMESPACE=$1
RELEASE=$2
PHP_IMAGE=$3
SUFFIX=${4:-$(date +%s)}
FULLNAME="${RELEASE}-magento"
JOB_NAME="${FULLNAME}-builder-${SUFFIX}"
COMPILE=${MAGENTO_BUILDER_COMPILE:-0}
BUILD_STATIC=${MAGENTO_BUILD_STATIC:-0}
STATIC_LOCALES=${MAGENTO_STATIC_LOCALES:-en_US}
STATIC_JOBS=${MAGENTO_STATIC_JOBS:-4}
TTL=${MAGENTO_BUILDER_TTL:-300}

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
$(if [[ "$TTL" != "0" ]]; then echo "  ttlSecondsAfterFinished: ${TTL}"; fi)
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: builder
          image: ${PHP_IMAGE}
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: ${FULLNAME}-env
            - secretRef:
                name: ${FULLNAME}-secrets
          command:
            - /bin/bash
            - -c
          args:
            - |
              set -euo pipefail
              MAGENTO_BUILDER_COMPILE=${COMPILE}
              MAGENTO_BUILD_STATIC=${BUILD_STATIC}
              MAGENTO_STATIC_LOCALES="${STATIC_LOCALES}"
              MAGENTO_STATIC_JOBS=${STATIC_JOBS}
              if [[ "\${MAGENTO_BUILDER_COMPILE}" == "1" ]]; then
                php bin/magento deploy:mode:set developer --skip-compilation || true
                php bin/magento setup:upgrade --keep-generated
                php bin/magento setup:di:compile
                php bin/magento deploy:mode:set production --skip-compilation || true
              fi
              if [[ "\${MAGENTO_BUILD_STATIC}" == "1" ]]; then
                php bin/magento setup:static-content:deploy -f --jobs="\${MAGENTO_STATIC_JOBS}" \${MAGENTO_STATIC_LOCALES}
              fi
              mkdir -p /mnt/generated /mnt/vardi
              rm -rf /mnt/generated/* /mnt/vardi/*
              if [[ -d generated ]]; then
                cp -a generated/. /mnt/generated/
              fi
              if [[ -d var/di ]]; then
                cp -a var/di/. /mnt/vardi/ || true
              fi
              mkdir -p /mnt/pubstatic
              rm -rf /mnt/pubstatic/*
              if [[ -d pub/static ]]; then
                cp -a pub/static/. /mnt/pubstatic/
              fi
          volumeMounts:
            - name: generated
              mountPath: /mnt/generated
            - name: vardi
              mountPath: /mnt/vardi
            - name: pubstatic
              mountPath: /mnt/pubstatic
      volumes:
        - name: generated
          persistentVolumeClaim:
            claimName: ${FULLNAME}-generated
        - name: vardi
          persistentVolumeClaim:
            claimName: ${FULLNAME}-vardi
        - name: pubstatic
          persistentVolumeClaim:
            claimName: ${FULLNAME}-pubstatic
EOF

echo "[builder] 等待 Job ${JOB_NAME} 完成……"
kubectl -n "${NAMESPACE}" logs -f job/"${JOB_NAME}" || true
kubectl -n "${NAMESPACE}" wait --for=condition=complete job/"${JOB_NAME}" --timeout=15m
echo "[builder] Job 已完成，可通过 'kubectl -n ${NAMESPACE} delete job ${JOB_NAME}' 清理"
